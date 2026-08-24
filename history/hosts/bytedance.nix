# Historical Home Manager profile recovered from my ByteDance work machine.
{ ... }:
{
  home.username = "bytedance";
  home.homeDirectory = "/Users/bytedance";

  home.sessionVariables = {
    GOPRIVATE = "*.byted.org";
    GONOPROXY = "*.byted.org";
    GONOSUMDB = "*.byted.org";
  };
}
