rockspec_format = "3.0"
package = "jsonata"
version = "scm-1"
source = {
  url = "git+https://github.com/flearc/lua-jsonata.git",
}
description = {
  summary = "A pure-Lua implementation of the JSONata query and transformation language",
  homepage = "https://github.com/flearc/lua-jsonata",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
}
test_dependencies = {
  "busted",
}
build = {
  type = "builtin",
  modules = {
    ["jsonata"] = "src/jsonata/init.lua",
    ["jsonata.errors"] = "src/jsonata/errors.lua",
    ["jsonata.value"] = "src/jsonata/value.lua",
    ["jsonata.adapter"] = "src/jsonata/adapter.lua",
    ["jsonata.tokenizer"] = "src/jsonata/tokenizer.lua",
    ["jsonata.parser"] = "src/jsonata/parser.lua",
    ["jsonata.environment"] = "src/jsonata/environment.lua",
    ["jsonata.functions"] = "src/jsonata/functions/init.lua",
    ["jsonata.functions.helpers"] = "src/jsonata/functions/helpers.lua",
    ["jsonata.functions.boolean"] = "src/jsonata/functions/boolean.lua",
    ["jsonata.functions.string"] = "src/jsonata/functions/string.lua",
    ["jsonata.functions.numeric"] = "src/jsonata/functions/numeric.lua",
    ["jsonata.functions.aggregation"] = "src/jsonata/functions/aggregation.lua",
    ["jsonata.functions.array"] = "src/jsonata/functions/array.lua",
    ["jsonata.functions.object"] = "src/jsonata/functions/object.lua",
    ["jsonata.evaluator"] = "src/jsonata/evaluator.lua",
  },
}
test = {
  type = "busted",
}
