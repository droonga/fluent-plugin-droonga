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

require "droonga/plugins/groonga/select"

class GroongaSelectAdapterInputTest < Test::Unit::TestCase
  private
  def convert(select_request)
    converter = Droonga::Plugins::Groonga::Select::RequestConverter.new
    converter.convert(select_request)
  end

  class OutputColumnsTest < self
    def assert_attributes(expected_attributes, output_columns)
      select_request = {
        "table" => "EmptyTable",
        "output_columns" => output_columns,
      }

      expected_search_request = {
        "queries" => {
          "EmptyTable_result" => {
            "source"   => "EmptyTable",
            "output"   => {
              "elements"   => [
                "startTime",
                "elapsedTime",
                "count",
                "attributes",
                "records",
              ],
              "attributes" => expected_attributes,
              "offset" => 0,
              "limit" => 10,
            },
          },
        },
      }
      assert_equal(expected_search_request, convert(select_request))
    end

    def test_multiple_columns
      assert_attributes(["_id", "_key"], "_id,_key")
    end

    class FunctionTest < self
      def test_single_argument
        assert_attributes(["snippet_html(content)"], "snippet_html(content)")
      end

      def test_with_columns
        assert_attributes(["_id","_key","snippet_html(content)"], "_id,_key,snippet_html(content)")
      end
    end
  end

  class MatchColumnsTest < self
    def assert_matchTo(expected_matchTo, match_columns)
      select_request = {
        "table"          => "EmptyTable",
        "match_columns"  => match_columns,
        "query"          => "QueryTest",
        "output_columns" => "_id",
      }

      expected_search_request = {
        "queries" => {
          "EmptyTable_result" => {
            "source"   => "EmptyTable",
            "condition"=> {
              "query"  => "QueryTest",
              "matchTo"=> expected_matchTo,
              "defaultOperator"=> "&&",
              "allowPragma"=> false,
              "allowColumn"=> true,
            },
            "output"   => {
              "elements"   => [
                "startTime",
                "elapsedTime",
                "count",
                "attributes",
                "records",
              ],
              "attributes" => ["_id"],
              "offset" => 0,
              "limit" => 10,
            },
          },
        },
      }
      assert_equal(expected_search_request, convert(select_request))
    end

    def test_single_column
      assert_matchTo(["_key"], "_key")
    end

    def test_multiple_columns
      assert_matchTo(["_key", "content"], "_key || content")
    end
  end

  class OffsetTest < self
    def assert_offset(expected_offset, offset)
      select_request = {
        "table"          => "EmptyTable",
        "output_columns" => "_id",
      }
      select_request["offset"] = offset unless offset.nil?

      expected_search_request = {
        "queries" => {
          "EmptyTable_result" => {
            "source"   => "EmptyTable",
            "output"   => {
              "elements"   => [
                "startTime",
                "elapsedTime",
                "count",
                "attributes",
                "records",
              ],
              "attributes" => ["_id"],
              "offset" => expected_offset,
              "limit" => 10,
            },
          },
        },
      }
      assert_equal(expected_search_request, convert(select_request))
    end

    def test_zero
      assert_offset(0, "0")
    end

    def test_large
      assert_offset(100, "100")
    end

    def test_integer
      assert_offset(100, 100)
    end

    def test_default
      assert_offset(0, nil)
    end
  end

  class LimitTest < self
    def assert_limit(expected_limit, limit)
      select_request = {
        "table"          => "EmptyTable",
        "output_columns" => "_id",
      }
      select_request["limit"] = limit unless limit.nil?

      expected_search_request = {
        "queries" => {
          "EmptyTable_result" => {
            "source"   => "EmptyTable",
            "output"   => {
              "elements"   => [
                "startTime",
                "elapsedTime",
                "count",
                "attributes",
                "records",
              ],
              "attributes" => ["_id"],
              "offset" => 0,
              "limit" => expected_limit,
            },
          },
        },
      }
      assert_equal(expected_search_request, convert(select_request))
    end

    def test_zero
      assert_limit(0, "0")
    end

    def test_large
      assert_limit(100, "100")
    end

    def test_negative
      assert_limit(-1, "-1")
    end

    def test_integer
      assert_limit(100, 100)
    end

    def test_default
      assert_limit(10, nil)
    end
  end
end
