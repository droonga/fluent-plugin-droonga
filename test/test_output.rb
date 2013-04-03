# Copyright (C) 2013 droonga project
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "fluent/plugin/out_droonga"

module OutputStub
  class Worker
    attr_reader :processed_record
    def initialize(response)
      @response = response
      @processed_record = nil
    end

    def process_message(record)
      @processed_record = record
      @response
    end

    def shutdown
    end
  end

  class Logger
    attr_reader :tag, :options
    attr_reader :posted_tag, :posted_message
    def initialize(tag, options)
      @tag = tag
      @options = options
    end

    def post(tag, message)
      @posted_tag = tag
      @posted_message = message
    end

    def close
    end
  end

  class Output < Fluent::DroongaOutput
    attr_reader :worker, :outputs
    def initialize(response)
      @response = response
      super()
    end

    def create_worker
      Worker.new(@response)
    end

    def create_logger(tag, options)
      Logger.new(tag, options)
    end
  end
end

class OutputTest < Test::Unit::TestCase
  setup
  def setup_fluent
    Fluent::Test.setup
  end

  def test_exec
    response = {}
    driver = create_driver("droonga.message", response)
    request = {"hello" => "world"}
    time = Time.parse("2012-10-26T08:45:42Z").to_i
    driver.run do
      driver.emit(request, time)
    end
    assert_equal(request, @output.worker.processed_record)
  end

  def test_replyTo
    response = {}
    driver = create_driver("droonga.message", response)
    request = {
      "id"      => "29",
      "replyTo" => "127.0.0.1:2929/droonga.meessage",
      "type"    => "search",
    }
    time = Time.parse("2012-10-26T08:45:42Z").to_i
    driver.run do
      driver.emit(request, time)
    end

    response_output = @output.outputs["127.0.0.1:2929"]
    response_logger = response_output[:logger]
    assert_equal([
                   "message",
                   {
                     :body => {:result => {}},
                     :inReplyTo => "29",
                     :statusCode => 200,
                     :type => "search.result",
                   },
                 ],
                 [
                   response_logger.posted_tag,
                   response_logger.posted_message,
                 ])
  end

  private
  def create_driver(tag, response)
    @output = OutputStub::Output.new(response)
    driver = Fluent::Test::OutputTestDriver.new(@output, tag)
    driver.configure(configuration)
    driver
  end

  def configuration
    <<-EOC
EOC
  end
end