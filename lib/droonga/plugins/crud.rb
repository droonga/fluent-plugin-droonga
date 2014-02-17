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

require "groonga"

require "droonga/plugin"
require "droonga/message_processing_error"

module Droonga
  module Plugins
    module CRUD
      Plugin.registry.register("crud", self)

      class Adapter < Droonga::Adapter
        input_message.pattern  = ["type", :equal, "add"]
        output_message.pattern = ["body.success", :exist]

        def adapt_output(output_message)
          success = output_message.body["success"]
          unless success.nil?
            output_message.body = output_message.body["success"]
          end
        end
      end

      class Planner < Droonga::Planner
        message.pattern = ["type", :equal, "add"]

        def plan(message)
          scatter(message,
                  :key => message["body"]["key"] || rand.to_s,
                  :reduce => {
                    "success" => "and"
                  })
        end
      end

      class Handler < Droonga::Handler
        message.type = "add"

        class MissingTableParameter < BadRequest
          def initialize
            super("\"table\" must be specified.")
          end
        end

        class MissingPrimaryKeyParameter < BadRequest
          def initialize(table_name)
            super("\"key\" must be specified. " +
                    "The table #{table_name.inspect} requires a primary key for a new record.")
          end
        end

        class UnknownTable < NotFound
          def initialize(table_name)
            super("The table #{table_name.inspect} does not exist in the dataset.")
          end
        end

        class InvalidValue < BadRequest
          def initialize(column, value, request)
            super("The column #{column.inspect} cannot store the value #{value.inspect}.",
                  request)
          end
        end

        class UnknownColumn < NotFound
          def initialize(column, table, request)
            super("The column #{column.inspect} does not exist in the table #{table.inspect}.",
                  request)
          end
        end

        def handle(message, messenger)
          succeeded = process_add(message.request)
          outputs = {
            "success" => succeeded,
          }
          messenger.emit(outputs)
        end

        private
        def process_add(request)
          raise MissingTableParameter.new unless request.include?("table")

          table = @context[request["table"]]
          raise UnknownTable.new(request["table"]) unless table

          if table.support_key?
            unless request.include?("key")
              raise MissingPrimaryKeyParameter.new(request["table"])
            end
          end

          add_record(table, request)
          true
        end

        def add_record(table, request)
          record = nil
          if table.support_key?
            record = table.add(request["key"])
          else
            record = table.add
          end
          (request["values"] || []).each do |column, value|
            begin
              record[column] = value
            rescue ::Groonga::InvalidArgument => error
              record.delete if record.added?
              raise InvalidValue.new(column, value, request)
            rescue ArgumentError => error
              record.delete if record.added?
              raise InvalidValue.new(column, value, request)
            rescue ::Groonga::NoSuchColumn => error
              record.delete if record.added?
              raise UnknownColumn.new(column, request["table"], request)
            end
          end
        end
      end
    end
  end
end
