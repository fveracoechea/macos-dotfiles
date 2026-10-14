require("git"):setup();
local mocha = require("yatline-catppuccin"):setup("mocha");
require("yatline"):setup({
  theme = mocha,
});
