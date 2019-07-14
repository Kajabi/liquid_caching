require 'bundler/setup'
require 'liquid'
require 'pry'
require_relative "../lib/liquid_caching"

class Example
  def to_liquid
    ExampleDrop.new
  end
end

class ExampleDrop < ::Liquid::Drop
  extend LiquidCaching::UncacheableDrop

  def bar
    # puts caller
    # "BAR!!!"
    "UNCACHEABLE_VALUE"
  end
end

RSpec.describe "cached include" do
  let(:fs) { double(:file_system) }
  let(:context) { Liquid::Context.new({"foo" => Example.new}) }

  before do
    context.registers[:file_system] = fs
    allow(fs).to receive(:method).with(:read_template_file) { double(:method, arity: 1) }
  end

  it "works" do
    template = Liquid::Template.parse(<<~EOF)
      {% include 'aaa' %}
      {% include 'bbb' %}
    EOF

    expect(fs).to receive(:read_template_file).with('aaa') { "{{ foo.bar }}" }
    expect(fs).to receive(:read_template_file).with('bbb') { "hello" }

    context.registers["precompile"] = true
    precompiled_template = template.render!(context)

    expect(precompiled_template).to eq <<~EOF
      {% include 'aaa' %}
      hello
    EOF

    template = Liquid::Template.parse(precompiled_template)
    context.registers["precompile"] = false
    result = template.render!(context)

    expect(result).to eq <<~EOF
      UNCACHEABLE_VALUE
      hello
    EOF

    # puts context.registers["precompile_result"]
  end

  it "nesting" do
    template = Liquid::Template.parse(<<~EOF)
      {% include 'aaa' %}
    EOF

    expect(fs).to receive(:read_template_file).with('aaa') { <<~EOF }
      {% include 'bbb' %}
      {% include 'ccc' %}
    EOF
    expect(fs).to receive(:read_template_file).with('bbb') { "{{ foo.bar }}" }
    expect(fs).to receive(:read_template_file).with('ccc') { "hello" }

    context.registers["precompile"] = true
    precompiled_template = template.render!(context)

    expect(precompiled_template).to eq <<~EOF
      {% include 'bbb' %}
      hello
    EOF

    template = Liquid::Template.parse(precompiled_template)
    context.registers["precompile"] = false
    result = template.render!(context)

    expect(result).to eq <<~EOF
      UNCACHEABLE_VALUE
      hello
    EOF

    puts context.registers["precompile_result"]
  end

  # it "nesting" do
  #   template = Liquid::Template.parse(<<-EOF)
  #     {% include 'aaa' %}
  #     {% include 'safe' %}
  #   EOF
  #
  #   expect(fs).to receive(:read_template_file).with('aaa') { "{% include 'unsafe' %}" }
  #   expect(fs).to receive(:read_template_file).with('unsafe') { "{{ foo }}\n{% include 'safe' %}" }
  #
  #   expect(fs).to receive(:read_template_file).with('safe') { "hello" }
  #
  #   result = template.render!(context)
  #
  #   puts "-----------"
  #   p result
  # end
end
