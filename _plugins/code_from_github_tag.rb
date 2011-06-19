module Jekyll
  class CodeFromGithubTag < Liquid::Tag

    def initialize(tag_name, github_link, tokens)
      super
      _parse_and_store_link(github_link)
    end

    def render(context)

    end

    def _parse_and_store_link(github_link)
      @link = "https://github.com/#{github_link}"
      parsed_link = URI.parse(@link)
      @start_line, @end_line = parsed_link.fragment.sub(/^L/, '').split('-')
      @project_name = github_link.split('/')[1]
    end
  end
end

Liquid::Template.register_tag('code_from_github', Jekyll::CodeFromGithubTag)
