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

require "droonga/catalog_loader"

module Droonga
  class << self
    def catalog
      @catalog ||= Catalog.load
    end
  end

  module Catalog
    PATH = "catalog.json"

    class << self
      def load(path=nil)
        path = ENV["DROONGA_CATALOG"] || PATH
        path = File.expand_path(path)
        loader = CatalogLoader.new(path)
        loader.load
      end
    end
  end
end
