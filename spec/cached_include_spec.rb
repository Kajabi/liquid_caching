require 'bundler/setup'
require 'liquid'
require 'pry'
require_relative "../lib/liquid_caching"

class UncacheableObject
  def to_liquid
    UncacheableObjectDrop.new
  end
end

class UncacheableObjectDrop < ::Liquid::Drop
  extend LiquidCaching::UncacheableDrop

  def bar
    "UNCACHEABLE_VALUE"
  end
end

RSpec.describe "cached include" do
  let(:fs) { double(:file_system) }
  let(:context) { Liquid::Context.new({"foo" => UncacheableObject.new}) }

  before do
    context.registers[:file_system] = fs
    # Liquid does some introspection for backwards-compatability
    allow(fs).to receive(:method).with(:read_template_file) { double(:method, arity: 1) }
  end

  context "single level template" do
    let(:template) do
      Liquid::Template.parse(<<~EOF)
        {% include 'aaa' %}
        {% include 'bbb' %}
      EOF
    end

    before do
      allow(fs).to receive(:read_template_file).with('aaa') { "{{ foo.bar }}" }
      allow(fs).to receive(:read_template_file).with('bbb') { "hello" }
    end

    it "renders normally when caching is not enabled" do
      result = template.render!(context)

      expect(result).to eq <<~EOF
        UNCACHEABLE_VALUE
        hello
      EOF
    end

    it "renders a cacheable template where uncacheable includes are left unrendered" do
      context.registers[:caching] = true
      cacheable_template = template.render!(context)

      expect(cacheable_template).to eq <<~EOF
        {% include 'aaa' %}
        hello
      EOF
    end

    it "provides templates that were uncacheable for later use" do
      context.registers[:caching] = true
      cacheable_template = template.render!(context)

      expect(context.registers[:cached_file_system].rendered_results).to eq({
        "aaa" => "UNCACHEABLE_VALUE"
      })
    end
  end

  context "nested template" do
    # |- aaa
    #    |- bbb
    #       |- ccc  <- uncacheable method called
    # |- zzz
    let(:template) do
      Liquid::Template.parse(<<~EOF)
        {% include 'aaa' %}
        {% include 'zzz' %}
      EOF
    end

    before do
      allow(fs).to receive(:read_template_file).with('aaa') { <<~EOF }
        aaa start
        {% include 'bbb' %}
        aaa end
      EOF
      allow(fs).to receive(:read_template_file).with('bbb') { <<~EOF }
        bbb start
        {% include 'ccc' %}
        bbb end
      EOF
      allow(fs).to receive(:read_template_file).with('ccc') { <<~EOF }
        ccc start
        {{ foo.bar }}
        ccc end
      EOF
      allow(fs).to receive(:read_template_file).with('zzz') { "zzz" }
    end

    it "renders normally when caching is not enabled" do
      result = template.render!(context)

      expect(result).to eq <<~EOF
        aaa start
        bbb start
        ccc start
        UNCACHEABLE_VALUE
        ccc end

        bbb end

        aaa end

        zzz
      EOF
    end

    it "renders a cacheable template where uncacheable includes are left unrendered" do
      context.registers[:caching] = true
      cacheable_template = template.render!(context)

      expect(cacheable_template).to eq <<~EOF
        {% include 'aaa' %}
        zzz
      EOF
    end

    it "provides templates that were uncacheable for later use" do
      context.registers[:caching] = true
      cacheable_template = template.render!(context)

      expect(context.registers[:cached_file_system].rendered_results).to eq({
        "aaa" => "aaa start\n{% include 'bbb' %}\naaa end\n",
        "bbb" => "bbb start\n{% include 'ccc' %}\nbbb end\n",
        "ccc" => "ccc start\nUNCACHEABLE_VALUE\nccc end\n",
      })
    end

    it "reduces the expense of a second render by storing a reusable file_system containing rendered results" do
      context.registers[:caching] = true
      cacheable_template = template.render!(context)

      new_context = Liquid::Context.new
      new_context.registers[:file_system] = context.registers[:cached_file_system]
      result = Liquid::Template.parse(cacheable_template).render!(new_context)

      expect(result).to eq <<~EOF
        aaa start
        bbb start
        ccc start
        UNCACHEABLE_VALUE
        ccc end

        bbb end

        aaa end

        zzz
      EOF
    end
  end
end
