require File.dirname(__FILE__) + '/../ext/fiber18'
require 'rubygems'
require 'eventmachine'

module EventMachine
  
  def self.spec_backend=( backend )
    @spec_backend = backend
  end
  
  def self.spec_backend
    @spec_backend
  end
  
  def self.spec *args, &blk
    raise ArgumentError, 'block required' unless block_given?
    raise 'EventMachine reactor already running' if EM.reactor_running?

    spec_backend.spec( args, blk )
  end
  class << self; alias :describe :spec; end

  def self.bacon( *args, &block )
    require File.dirname(__FILE__) + '/spec/bacon'
    self.spec_backend = EventMachine::Spec::Bacon
    self.spec( args, &block )
  end

end

module EventMachine
  module Spec
    module Bacon
      
      def self.spec( args, blk )
        EM.run do
          ::Bacon.summary_on_exit
          ($em_spec_fiber = Fiber.new{
                              ::Bacon::FiberedContext.new(args.join(' '), &blk).run
                              EM.stop_event_loop
                            }).resume
        end
      end
      
    end
  end
end

class Bacon::FiberedContext < Bacon::Context

  SpecTimeoutExceededError = Class.new(RuntimeError)

  def default_timeout(timeout)
    $_em_default_time_to_finish = timeout
  end

  def cancel_timer
    EM.cancel_timer($_em_timer) if $_em_timer
  end

  def timeout(time_to_run)
    cancel_timer
    $_em_timer = EM.add_timer(time_to_run) { done(false) }
  end

  def it *args
    super{
      if block_given?
        if $_em_default_time_to_finish
          timeout($_em_default_time_to_finish)
        end
        yield
        Fiber.yield
      end
    }
  end
  
  def describe(*args, &block)
    context = Bacon::FiberedContext.new(args.join(' '), &block)
    @before.each { |b| context.before(&b) }
    @after.each { |b| context.after(&b) }
    context.run
  end

  def done(succeed = true)
    cancel_timer
    EM.next_tick{
      if succeed 
        :done.should == :done
      else
        should.flunk
      end
      $em_spec_fiber.resume if $em_spec_fiber
    }
  end
end