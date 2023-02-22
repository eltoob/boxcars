# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  class ActiveRecord < EngineBoxcar
    # the description of this engine boxcar
    ARDESC = "useful for when you need to query a database for an application named %<name>s."
    LOCKED_OUT_MODELS = %w[ActiveRecord::SchemaMigration ActiveRecord::InternalMetadata ApplicationRecord].freeze
    attr_accessor :connection, :input_key, :requested_models, :read_only
    attr_reader :except_models

    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param models [Array<ActiveRecord::Model>] The models to use for this boxcar. Will use all if nil.
    # @param read_only [Boolean] Whether to use read only models. Defaults to true.
    # @param kwargs [Hash] Any other keyword arguments. These can include:
    #   :name, :description, :prompt, :input_key, :output_key and :except_models
    def initialize(engine: nil, models: nil, read_only: true, **kwargs)
      check_models(models)
      @except_models = LOCKED_OUT_MODELS + kwargs[:except_models].to_a
      @read_only = read_only
      @input_key = kwargs[:input_key] || :question
      @output_key = kwargs[:output_key] || :answer
      the_prompt = kwargs[prompt] || my_prompt
      name = kwargs[:name] || "Data"
      super(name: name,
            description: kwargs[:description] || format(ARDESC, name: name),
            engine: engine,
            prompt: the_prompt,
            output_key: output_key)
    end

    # the input keys for the prompt
    # @return [Array<Symbol>] The input keys for the prompt.
    def input_keys
      [input_key]
    end

    # the output keys for the prompt
    # @return [Array<Symbol>] The output keys for the prompt.
    def output_keys
      [output_key]
    end

    # call the boxcar
    # @param inputs [Hash] The inputs to the boxcar.
    # @return [Hash] The outputs from the boxcar.
    def call(inputs:)
      t = predict(question: inputs[input_key], top_k: 5, model_info: model_info, stop: ["Answer:"]).strip
      answer = get_answer(t)
      puts answer.colorize(:magenta)
      { output_key => answer }
    end

    private

    def read_only?
      read_only
    end

    def check_models(models)
      if models.is_a?(Array) && models.length.positive?
        @requested_models = models
        models.each do |m|
          raise ArgumentError, "model #{m} needs to be an Active Record model" unless m.ancestors.include?(::ActiveRecord::Base)
        end
      elsif models
        raise ArgumentError, "models needs to be an array of Active Record models"
      end
    end

    def wanted_models
      the_models = requested_models || ::ActiveRecord::Base.descendants
      the_models.reject { |m| except_models.include?(m.name) }
    end

    def models
      models = wanted_models.map(&:name)
      models.join(", ")
    end

    def model_info
      models = wanted_models
      models.pretty_inspect
    end

    # to be safe, we wrap the code in a transaction and rollback
    # rubocop:disable Lint/SuppressedException
    def wrap_in_transaction
      ::ActiveRecord::Base.transaction do
        yield
      ensure
        raise ::ActiveRecord::Rollback
      end
    rescue ::ActiveRecord::Rollback
    end
    # rubocop:enable Lint/SuppressedException

    def safe_to_run?(code)
      return true unless read_only?

      bad_words = %w[delete delete_all destroy destroy_all update update_all upsert upsert_all create save insert drop alter truncate
                     revoke commit rollback reset execute].freeze
      without_strings = code.gsub(/('([^'\\]*(\\.[^'\\]*)*)'|"([^"\\]*(\\.[^"\\]*)*"))/, 'XX')
      word_list = without_strings.split(/[.,()]/)

      bad_words.each do |w|
        if word_list.include?(w)
          puts "code included destructive instruction: #{w} #{code}"
          return false
        end
      end

      true
    end

    def get_active_record_answer(text)
      code = text[/^ARCode: (.*)/, 1]
      puts code.colorize(:yellow)
      raise SecurityError, "Can not run code that makes changes in read-only mode" unless safe_to_run?(code)

      # rubocop:disable Security/Eval
      output = eval code
      # rubocop:enable Security/Eval
      output = 0 if output.is_a?(Array) && output.empty?
      output = output.first if output.is_a?(Array) && output.length == 1
      "Answer: #{output.inspect}"
    rescue StandardError => e
      "Error: #{e.message}"
    end

    def get_answer(text)
      case text
      when /^ARCode:/
        get_active_record_answer(text)
      when /^Answer:/
        text
      else
        raise Boxcars::Error "Unknown format from engine: #{text}"
      end
    end

    TEMPLATE = <<~IPT
      Given an input question, first create a syntactically correct Rails Active Record code to run,
      then look at the results of the code and return the answer. Unless the user specifies
      in her question a specific number of examples she wishes to obtain, limit your code
      to at most %<top_k>s results.

      Never query for all the columns from a specific model, only ask for a the few relevant attributes given the question.

      Pay attention to use only the attribute names that you can see in the model description. Be careful to not query for attributes that do not exist.
      Also, pay attention to which attribute is in which model.

      Use the following format:
      Question: "Question here"
      ARCode: "Active Record code to run"
      Answer: "Final answer here"

      Only use the following Active Record models:
      %<model_info>s

      Question: %<question>s
    IPT

    # The prompt to use for the engine.
    def my_prompt
      @my_prompt ||= Prompt.new(input_variables: [:question, :top_k, :model_info], template: TEMPLATE)
    end
  end
end
