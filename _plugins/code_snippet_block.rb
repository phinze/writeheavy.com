require 'ruby-debug'
require 'uri'

module Jekyll

  class CodeSnippetBlock < HighlightBlock

    module Feature
      class GithubLink
        attr_reader :link, :path, :project, :tag

        def self.new_if_applicable(args)
          link_arg = args.detect { |a| match_arg?(a) }.to_s.split('=').last
          link_arg ? new(link_arg) : nil
        end

        def self.match_arg?(str)
          str =~ /^githublink=/
        end

        def initialize(link_arg)
          _parse_and_store_github_link(link_arg)
        end

        def remove_arg?(arg)
          self.class.match_arg?(arg)
        end

        def apply(code)
          code.sub(%r(</pre>\s+</div>\s+\Z), "#{_render_link}</pre></div>")
        end

        def _parse_and_store_github_link(link_arg)
          return nil unless link_arg

          @link = URI.parse("https://github.com/#{link_arg}")
          path_parts = @link.path.split('/')
          @project = path_parts[1]
          @tag = path_parts[4]
          @path = path_parts[5..-1].join('/')
        end

        def _render_link
          %(<a class="code-attribution" href="#{link}">#{path} (#{project} #{tag})</a>)
        end
      end

      class InvertColors
        def self.new_if_applicable(args)
          new if args.include?('invert_colors')
        end

        def remove_arg?(arg)
          arg == 'invert_colors'
        end

        def apply(code)
          %(<div class="inverse">#{code}</div>)
        end
      end
    end

    def all_features
      [Feature::GithubLink, Feature::InvertColors]
    end

    def initialize(tag_name, markup, tokens)
      args = markup.split
      @features = all_features.map { |feature| feature.new_if_applicable(args) }.compact
      super tag_name, _without_feature_args(markup), tokens
    end

    def render_pygments(context, code)
      rendered_code = super
      @features.inject(rendered_code) { |code, feature| feature.apply(code) }
    end

    def _without_feature_args(markup)
      markup.split.reject { |a| @features.any? { |f| f.remove_arg?(a) }}.join(' ')
    end

  end
end

Liquid::Template.register_tag('codesnippet', Jekyll::CodeSnippetBlock)
