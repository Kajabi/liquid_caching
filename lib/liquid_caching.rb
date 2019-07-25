module LiquidCaching
  # Including this in a Liquid::Drop subclass means that any method called on
  # the Drop during template execution will mark the proceeding stack "uncacheabe".
  module UncacheableDrop
    def new(*)
      UncacheableDecorator.new(super)
    end
  end

  # Decorator intended to wrap a Liquid::Drop. Intercepts most method calls to
  # mark the stack as uncacheable.
  class UncacheableDecorator < BasicObject
    def initialize(source)
      @source = source
    end

    def to_liquid
      @source = @source.to_liquid
      self
    end

    # Intercept the context setter, as source.context is private.
    def context=(context)
      @context = context
      @source.context = context
    end

    def method_missing(method, *args, &block)
      @context && @context.registers[:template_stack]&.uncacheable!
      @source.public_send(method, *args, &block)
    end
  end

  # Drop-in replacement for Liquid's `include` that uses the render context's
  # LiquidCaching::TemplateStack to determine if the partial can be cached.
  #
  # If the partial can be cached, it's rendered into the result normally.
  #
  # If the partial is uncacheable, the original `{% include ... %}` tag is
  # emitted to the output instead, resulting in a cacheable template.
  class CachedInclude < ::Liquid::Include
    def render(context)
      # TODO: account for variables passed to `include` in key (`@attributes` I believe)
      template_key = @template_name[1..-2] # unquote

      if context.registers[:caching]
        stack = context.registers[:template_stack] ||= TemplateStack.new
        cached_file_system = context.registers[:cached_file_system] ||= CachedFileSystem.new

        result, cacheable = stack.add(template_key) { super }

        if !cacheable
          cached_file_system.templates[template_key] = context.registers[:file_system].read_template_file(template_key)
          cached_file_system.rendered_results[template_key] = result
          "{% #{raw.strip} %}"
        else
          result
        end
      else
        super
      end
    end
  end
  ::Liquid::Template.register_tag("include", CachedInclude)

  class TemplateStack
    Item = Struct.new(:name, :cacheable)

    def initialize
      @stack = []
    end

    # Marks this and all templates currently in the stack as "uncacheable".
    def uncacheable!
      @stack.each { |t| t.cacheable = false }
    end

    # Returns true if the current stack is cacheable up to this point.
    def cacheable?
      last.nil? || last.cacheable
    end

    # Adds a template to the stack.
    def add(template_name)
      @stack << Item.new(template_name, true)

      begin
        result = yield
        return [result, cacheable?]
      ensure
        @stack.pop
      end
    end

    def last
      @stack.last
    end
  end

  # Produced as a side effect of CachedInclude.
  class CachedFileSystem
    # Intended to be serialized along with the cacheable template so future
    # renders don't need to look up the uncached templates.
    attr_reader :templates

    # Stores rendered templates from the first cache miss to reduce the expense
    # of the subsequent render of the cacheable template.
    attr_reader :rendered_results

    def initialize(templates = {})
      @templates = templates
      @rendered_results = {}
    end

    def read_template_file(file_path)
      rendered_results[file_path] || templates[file_path]
    end
  end
end
