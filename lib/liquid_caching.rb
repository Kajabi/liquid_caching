module LiquidCaching
  module UncacheableDrop
    def new(*)
      UncacheableDecorator.new(super)
    end
  end

  class UncacheableDecorator < BasicObject
    def initialize(source)
      @source = source
    end

    def to_liquid
      @source = @source.to_liquid
      self
    end

    def context=(context)
      @context = context
      @source.context = context
    end

    def method_missing(method, *args, &block)

      if @context && @context.registers["template_stack"]
        # $stdout.puts "uncacheable: #{@source.class}##{method} called"
        @context.registers["template_stack"].uncacheable
      end

      @source.public_send(method, *args, &block)
    end
  end

  class TemplateStack
    Item = Struct.new(:name, :cacheable)

    def initialize
      @stack = []
    end

    def uncacheable
      # @stack.each { |item| item.cacheable = false }
      @stack.last.cacheable = false
    end

    def <<(template_name)
      @stack << Item.new(template_name, true)
    end

    def pop
      @stack.pop
    end

    def last
      @stack.last
    end
  end

  class CachedInclude < ::Liquid::Include
    def render(context)
      stack = (context.registers["template_stack"] ||= TemplateStack.new)
      ret = nil
      cacheable = nil

      begin
        stack << @template_name
        ret = instance_eval "super", @template_name, 0
        cacheable = stack.last.cacheable
        puts "#{@template_name} is #{cacheable ? 'cacheable' : '**NOT** cacheable'}"
      ensure
        stack.pop
      end

      if context.registers["precompile"] && !cacheable
        (context.registers["precompile_result"] ||= {})[@template_name] = ret
        "{% #{raw.strip} %}"
      else
        ret
        # "UNCACHEABLE INCLUDE"
      end
    end
  end
  ::Liquid::Template.register_tag('include', CachedInclude)
end
