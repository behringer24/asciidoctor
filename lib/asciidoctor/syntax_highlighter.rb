module Asciidoctor
  # Public: A pluggable adapter for integrating a syntax (aka code) highlighter into AsciiDoc processing.
  #
  # There are two types of syntax highlighter adapters. The first performs syntax highlighting during the convert phase.
  # This adapter type must define a highlight? method that returns true. The companion highlight method will then be
  # called to handle the :specialcharacters substitution for source blocks. The second assumes syntax highlighting is
  # performed on the client (e.g., when the HTML document is loaded). This adapter type must define a docinfo? method
  # that returns true. The companion docinfo method will then be called to insert markup into the output document. The
  # docinfo functionality is available to both adapter types.
  #
  # Asciidoctor provides several built-in adapters, including coderay, pygments, highlight.js, html-pipeline, and
  # prettify. Additional adapters can be registered using SyntaxHighlighter.register or by supplying a custom factory.
  module SyntaxHighlighter
    # Public: Returns the String name of this syntax highlighter for referencing it in messages and option names.
    attr_reader :name

    def initialize name, backend = 'html5', opts = {}
      @name = @pre_class = name
    end

    # Public: Indicates whether this syntax highlighter has docinfo (i.e., markup) to insert into the output document at
    # the specified location.
    #
    # location - The Symbol representing the location slot (:head or :footer).
    #
    # Returns a Boolean indicating whether the docinfo method should be called for this location.
    def docinfo? location; end

    # Public: Generates docinfo markup to insert in the output document at the specified location.
    #
    # location - The Symbol representing the location slot (:head or :footer).
    #
    # Return the String markup to insert.
    def docinfo location
      raise ::NotImplementedError, %(#{SyntaxHighlighter.name} must implement the docinfo method if the docinfo? method returns true)
    end

    # Public: Indicates whether highlighting is handled by this syntax highlighter or by the client.
    #
    # Returns a Boolean indicating whether the highlight method should be used to handle the :specialchars substitution.
    def highlight?; end

    # Public: Highlights the specified source when this source block is being converted.
    #
    # If the source contains callout marks, the caller assumes the source remains on the same lines and no closing tags
    # are added to the end of each line. If the source gets shifted by one or more lines, this method must return a
    # tuple containing the highlighted source and the number of lines by which the source was shifted.
    #
    # node   - The source Block to syntax highlight.
    # source - The raw source text String of this source block (after preprocessing).
    # lang   - The source language String specified on this block (e.g., ruby).
    # opts   - A Hash of options that control syntax highlighting:
    #          :callouts - A Hash of callouts extracted from the source, indexed by line number (1-based) (optional).
    #          :css_mode - The Symbol CSS mode (:class or :inline).
    #          :highlight_lines - A 1-based Array of Integer line numbers to highlight (i.e., tint) (optional).
    #          :line_numbers - A Symbol indicating whether line numbers are enabled (:table or :inline) (optional).
    #          :start_line_number - The Integer line number (1-based) to start with when numbering lines (default: 1).
    #          :style - The String style (aka theme) to use for colorizing the code (optional).
    #
    # Returns the highlighted source String or a tuple of the highlighted source String and an Integer line offset.
    def highlight node, source, lang, opts
      raise ::NotImplementedError, %(#{SyntaxHighlighter.name} must implement the highlight method if the highlight? method returns true)
    end

    # Public: Format the highlighted source for inclusion in an HTML document.
    #
    # node   - The source Block being processed.
    # lang   - The source language String for this Block (e.g., ruby).
    # opts   - A Hash of options that control syntax highlighting:
    #          :nowrap - A Boolean that indicates whether wrapping should be disabled (optional).
    #
    # Returns the highlighted source String wrapped in preformatted tags (e.g., pre and code)
    def format node, lang, opts
      raise ::NotImplementedError, %(#{SyntaxHighlighter.name} must implement the format method)
    end

    # Public: Indicates whether this syntax highlighter wants to write a stylesheet to disk.
    #
    # Only called if both the linkcss and copycss attributes are set on the document.
    #
    # doc - The Document in which this syntax highlighter is being used.
    #
    # Returns a Boolean indicating whether the write_stylesheet method should be called.
    def write_stylesheet? doc; end

    # Public: Writes the stylesheet to support the highlighted source(s) to disk.
    #
    # doc    - The Document in which this syntax highlighter is being used.
    # to_dir - The absolute String path of the stylesheet output directory.
    #
    # Returns nothing.
    def write_stylesheet doc, to_dir
      raise ::NotImplementedError, %(#{SyntaxHighlighter.name} must implement the write_stylesheet method if the write_stylesheet? method returns true)
    end

    private_class_method def self.included into
      into.extend Config
    end

    module Config
      # Public: Statically register the current class in the registry for the specified names.
      #
      # Returns nothing.
      private def register_for *names
        SyntaxHighlighter.register self, *names
      end
    end

    module Factory
      # Public: Associates the syntax highlighter class or object with the specified names.
      #
      # Returns nothing.
      def register syntax_highlighter, *names
        names.each {|name| registry[name] = syntax_highlighter }
      end

      # Public: Retrieves the syntax highlighter class or object registered for the specified name.
      #
      # name - The String name of the syntax highlighter to retrieve.
      #
      # Returns the SyntaxHighlighter class or instance registered for this name.
      def for name
        registry[name]
      end

      # Public: Resolves the name to a syntax highlighter instance, if found in the registry.
      #
      # name    - The String name of the syntax highlighter to create.
      # backend - The String name of the backend for which this syntax highlighter is being used (default: 'html5').
      # opts    - A Hash of options providing information about the context in which this syntax highlighter is used:
      #           :doc - The Document for which this syntax highlighter was created.
      #
      # Returns a SyntaxHighlighter instance for the specified name.
      def create name, backend = 'html5', opts = {}
        if (syntax_hl = self.for name)
          syntax_hl = syntax_hl.new name, backend, opts if ::Class === syntax_hl
          raise ::NameError, %(#{syntax_hl.class.name} must specify a value for `name') unless syntax_hl.name
          syntax_hl
        end
      end

      private def registry
        @registry ||= {}
      end
    end

    module DefaultFactory
      include Factory

      private

      def registry
        @@registry
      end

      @@registry = {}

      unless RUBY_ENGINE == 'opal'
        public

        def register *args
          @@mutex.owned? ? super : @@mutex.synchronize { super }
        end

        # In addition to retrieving the syntax highlighter class or object registered for the specified name, this
        # method will lazy require and register additional built-in implementations (coderay, pygments, and prettify).
        # Refer to {Factory#for} for parameters and return value.
        def for name
          @@registry.fetch name do
            @@mutex.synchronize do
              @@registry.fetch name do
                if (script_path = PROVIDED[name])
                  require_relative script_path
                  @@registry[name]
                else
                  @@registry[name] = nil
                end
              end
            end
          end
        end

        private

        @@mutex = ::Mutex.new

        PROVIDED = {
          'coderay' => 'syntax_highlighter/coderay',
          'prettify' => 'syntax_highlighter/prettify',
          'pygments' => 'syntax_highlighter/pygments',
        }
      end
    end

    class CustomFactory
      include Factory

      def initialize registry = nil
        @registry = registry
      end
    end

    class DefaultFactoryProxy < CustomFactory
      include DefaultFactory

      def for name
        (@registry.key? name) ? @registry[name] : super
      end
    end

    extend DefaultFactory # exports static methods

    class Base
      include SyntaxHighlighter

      def format node, lang, opts
        class_attr_val = opts[:nowrap] ? %(#{@pre_class} highlight nowrap) : %(#{@pre_class} highlight)
        if (transform = opts[:transform])
          pre = { 'class' => class_attr_val }
          code = lang ? { 'data-lang' => lang } : {}
          transform[pre, code]
          %(<pre#{pre.map {|k, v| %[ #{k}="#{v}"] }.join}><code#{code.map {|k, v| %[ #{k}="#{v}"] }.join}>#{node.content}</code></pre>)
        else
          %(<pre class="#{class_attr_val}"><code#{lang ? %[ data-lang="#{lang}"] : ''}>#{node.content}</code></pre>)
        end
      end
    end
  end
end

require_relative 'syntax_highlighter/highlightjs'
require_relative 'syntax_highlighter/html_pipeline' unless RUBY_ENGINE == 'opal'
