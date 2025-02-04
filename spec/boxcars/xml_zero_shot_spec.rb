# frozen_string_literal: true

RSpec.describe Boxcars::XMLZeroShot do
  let(:search) { Boxcars::GoogleSearch.new }
  let(:calculator) { Boxcars::Calculator.new }

  it "can execute an XML train" do
    train = described_class.new(boxcars: [search, calculator])

    VCR.use_cassette("xmlzeroshot") do
      question = "What is pi times the square root of the average high temperature in Austin TX in January?"
      expect(train.run(question)).to include("25.13")
    end
  end

  context "with sample helpdesk app" do
    let(:helpdesk) { Boxcars::ActiveRecord.new(models: [Comment, Ticket, User], name: "helpdesk") }

    it "can use a train to answer a question" do
      train = described_class.new(boxcars: [helpdesk, calculator, search])
      VCR.use_cassette("xmlzeroshot2") do
        question = "The number of comments from John for open tickets multiplied by pi to 5 decimal places."
        expect(train.run(question)).to include("6.2831")
      end
    end
  end

  context "with one car train with calculator" do
    let(:train) { described_class.new(boxcars: [calculator]) }

    it "can do complex math" do
      VCR.use_cassette("xmlzeroshot3") do
        question = "what is pi squared to 7 digits?"
        expect(train.run(question)).to include("9.8696044")
      end
    end
  end

  context "with one car train with calculator follow on question" do
    let(:train) { described_class.new(boxcars: [calculator], return_intermediate_steps: true) }

    it "can do complex math" do
      VCR.use_cassette("xmlzeroshot4") do
        question = "what is pi squared to 7 digits?"
        answer = train.conduct(question)
        expect(answer[:output]).to include("9.8696044")

        question = "what is the square root of the previous answer?"
        answer = train.conduct(question)
        expect(answer[:output]).to include("3.14159")
      end
    end
  end

  context "with one car train with calculator and anthropic" do
    let(:engine) { Boxcars::Anthropic.new }
    let(:train) { described_class.new(engine: engine, boxcars: [calculator]) }

    it "can do complex math" do
      VCR.use_cassette("xmlzeroshot5") do
        question = "what is pi squared to 7 digits?"
        expect(train.run(question)).to include("9.8696044")
      end
    end
  end

  context "with one car train with calculator follow on question with anthropic" do
    let(:engine) { Boxcars::Anthropic.new }
    let(:train) { described_class.new(boxcars: [calculator], engine: engine, return_intermediate_steps: true) }

    it "can do complex math" do
      VCR.use_cassette("xmlzeroshot6") do
        question = "what is pi squared to 7 digits?"
        answer = train.conduct(question)
        expect(answer[:output]).to include("9.8696044")

        question = "what is the square root of the previous answer?"
        answer = train.conduct(question)
        expect(answer[:output]).to include("3.14159")
      end
    end
  end
end
