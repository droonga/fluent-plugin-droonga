# Copyright (C) 2013-2014 Droonga Project
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

require "English"
require "tsort"

require "droonga/adapter_runner"
require "droonga/planner"
require "droonga/catalog"
require "droonga/collector"
require "droonga/farm"
require "droonga/session"
require "droonga/replier"
require "droonga/message_processing_error"
require "droonga/catalog_observer"
require "droonga/distributor"

module Droonga
  class Dispatcher
    attr_reader :name

    class MissingDatasetParameter < BadRequest
      def initialize
        super("\"dataset\" must be specified.")
      end
    end

    class UnknownCommand < BadRequest
      def initialize(command, dataset)
        super("The command #{command.inspect} is not available " +
                "for the dataset #{dataset.inspect}.")
      end
    end

    def initialize(options)
      @options = options
      @name = @options[:name]
      @loop = EventLoop.new
      @catalog_observer = CatalogObserver.new(@loop)
      @sessions = {}
      @current_id = 0
      @local = Regexp.new("^#{@name}")
      @adapter_runner = AdapterRunner.new(self,
                                          Droonga.catalog.input_adapter_options,
                                          Droonga.catalog.output_adapter_options)
      @farm = Farm.new(name, @loop, :dispatcher => self)
      @forwarder = Forwarder.new(@loop)
      @replier = Replier.new(@forwarder)
      @planner = Planner.new(self, Droonga.catalog.planner_options)
      @collector = Collector.new(Droonga.catalog.collector_options)
    end

    def start
      @forwarder.start
      @farm.start
      @loop_thread = Thread.new do
        @loop.run
      end
    end

    def shutdown
      @forwarder.shutdown
      @planner.shutdown
      @collector.shutdown
      @adapter_runner.shutdown
      @farm.shutdown
      @loop.stop
      @loop_thread.join
    end

    def process_message(message)
      @message = message
      if message["type"] == "dispatcher"
        process_internal_message(message["body"])
      else
        begin
          assert_valid_message
          process_input_message(message)
        rescue MessageProcessingError => error
          reply("statusCode" => error.status_code,
                "body"       => error.response_body)
        rescue => error
          formatted_error = MessageProcessingError.new("Unknown internal error")
          reply("statusCode" => formatted_error.status_code,
                "body"       => formatted_error.response_body)
          raise error
        end
      end
    end

    def forward(message, destination)
      $log.trace("#{log_tag}: forward start")
      @forwarder.forward(message, destination)
      $log.trace("#{log_tag}: forward done")
    end

    # Replies response to replyTo.
    #
    # @param [Hash] message
    #   The message to be replied. See {Replier#reply} for available keys.
    #
    #   The key-value pairs in request message are used as the default
    #   key-value pairs. For example, if the passed message doesn't
    #   include `id` key, `id` key's value is used in request message.
    #
    # @return [void]
    #
    # @see Replier#reply
    def reply(message)
      adapted_message = @adapter_runner.adapt_output(@message.merge(message))
      return if adapted_message["replyTo"].nil?
      @replier.reply(adapted_message)
    end

    def process_internal_message(message)
      id = message["id"]
      session = @sessions[id]
      if session
        session.receive(message["input"], message["value"])
      else
        steps = message["steps"]
        if steps
          session_planner = SessionPlanner.new(self, steps)
          session = session_planner.create_session(id, @collector)
          @sessions[id] = session
        else
          #todo: take cases receiving result before its query into account
        end
        session.start
      end
      @sessions.delete(id) if session.done?
    end

    def dispatch(message, destination)
      if local?(destination)
        process_internal_message(message)
      else
        @forwarder.forward(@message.merge("body" => message),
                           "type" => "dispatcher",
                           "to"   => destination)
      end
    end

    def dispatch_steps(steps)
      id = generate_id
      destinations = {}
      steps.each do |step|
        dataset = step["dataset"]
        if dataset
          routes = Droonga.catalog.get_routes(dataset, step)
          step["routes"] = routes
        else
          step["routes"] ||= [id]
        end
        routes = step["routes"]
        routes.each do |route|
          destinations[farm_path(route)] = true
        end
      end
      dispatch_message = { "id" => id, "steps" => steps }
      destinations.each_key do |destination|
        dispatch(dispatch_message, destination)
      end
    end

    def process_local_message(local_message)
      task = local_message["task"]
      partition_name = task["route"]
      step = task["step"]
      command = step["command"]
      descendants = {}
      step["descendants"].each do |name, routes|
        descendants[name] = routes.collect do |route|
          farm_path(route)
        end
      end
      local_message["descendants"] = descendants
      farm_message = @message.merge("body" => local_message,
                                    "type" => command)
      @farm.process(partition_name, farm_message)
    end

    def local?(route)
      route =~ @local
    end

    private
    def generate_id
      id = @current_id
      @current_id = id.succ
      return [@name, id].join('.#')
    end

    def farm_path(route)
      if route =~ /\A.*:\d+\/[^\.]+/
        $MATCH
      else
        route
      end
    end

    def process_input_message(message)
      adapted_message = @adapter_runner.adapt_input(message)
      plan = @planner.process(adapted_message["type"], adapted_message)
      distributor = Distributor.new(self)
      distributor.distribute(plan)
    rescue Droonga::Pluggable::UnknownPlugin => error
      raise UnknownCommand.new(error.command, message["dataset"])
    end

    def assert_valid_message
      raise MissingDatasetParameter.new unless @message.include?("dataset")
    end

    def log_tag
      "[#{Process.ppid}][#{Process.pid}] dispatcher"
    end

    class SessionPlanner
      attr_reader :steps

      def initialize(dispatcher, steps)
        @dispatcher = dispatcher
        @steps = steps
      end

      def create_session(id, collector)
        resolve_descendants
        tasks = []
        inputs = {}
        @steps.each do |step|
          step["routes"].each do |route|
            next unless @dispatcher.local?(route)
            task = {
              "route" => route,
              "step" => step,
              "n_of_inputs" => 0,
              "values" => {}
            }
            tasks << task
            (step["inputs"] || [nil]).each do |input|
              inputs[input] ||= []
              inputs[input] << task
            end
          end
        end
        Session.new(id, @dispatcher, collector, tasks, inputs)
      end

      def resolve_descendants
        @descendants = {}
        @steps.size.times do |index|
          step = @steps[index]
          (step["inputs"] || []).each do |input|
            @descendants[input] ||= []
            @descendants[input] << index
          end
          step["n_of_expects"] = 0
        end
        @steps.each do |step|
          descendants = {}
          (step["outputs"] || []).each do |output|
            descendants[output] = []
            @descendants[output].each do |index|
              @steps[index]["n_of_expects"] += step["routes"].size
              descendants[output].concat(@steps[index]["routes"])
            end
          end
          step["descendants"] = descendants
        end
      end
    end
  end
end
