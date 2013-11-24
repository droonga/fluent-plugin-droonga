# -*- coding: utf-8 -*-
#
# Copyright (C) 2013 Droonga Project
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

require "droonga/pluggable"
require "droonga/distributor_plugin"

module Droonga
  class Distributor
    include Pluggable

    def initialize(dispatcher, options={})
      @dispatcher = dispatcher
      @plugins = []
      @options = options
      # TODO: don't put the default distributions
      load_plugins(options[:distributors] || ["search", "crud", "groonga", "watch"])
    end

    def distribute(envelope)
      command = envelope["type"]
      process(command, envelope)
    end

    def post(message)
      @dispatcher.handle(message, [])
    end

    private
    def instantiate_plugin(name)
      DistributorPlugin.repository.instantiate(name, self)
    end

    def log_tag
      "[#{Process.pid}] distributor"
    end
  end
end