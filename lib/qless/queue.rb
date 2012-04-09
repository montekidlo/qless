require "qless/lua"
require "qless/job"
require "redis"
require "json"
require "uuid"
require "securerandom"

module Qless  
  # A configuration class associated with a qless client
  class Queue
    @@uuid = UUID.new
    attr_reader   :name
    attr_accessor :worker
    
    def initialize(name, client, worker)
      @client = client
      @name   = name
      @worker = worker
    end
    
    # Put the described job in this queue
    # Options include:
    # => priority (int)
    # => tags (array of strings)
    # => delay (int)
    def put(data, options={})
      @client._put.call([@name], [
        @@uuid.generate(:compact),
        JSON.generate(data),
        Time.now.to_i,
        (options[:priority] || 0),
        JSON.generate((options[:tags] || [])),
        (options[:delay] || 0),
        (options[:retries] || 5)
      ])
    end
    
    # Pop a work item off the queue
    def pop(count=nil)
      results = @client._pop.call([@name], [@worker, (count || 1), Time.now.to_i]).map { |j| Job.new(@client, JSON.parse(j)) }      
      count.nil? ? results[0] : results
    end
    
    # Peek at a work item
    def peek(count=nil)
      results = @client._peek.call([@name], [(count || 1), Time.now.to_i]).map { |j| Job.new(@client, JSON.parse(j)) }
      count.nil? ? results[0] : results
    end
    
    def running
      @client._jobs.call([], ['running', Time.now.to_i, @name])
    end
    
    def stalled
      @client._jobs.call([], ['stalled', Time.now.to_i, @name])
    end
    
    def scheduled
      @client._jobs.call([], ['scheduled', Time.now.to_i, @name])
    end
    
    def stats(date=nil)
      JSON.parse(@client._stats.call([], [@name, (date || Time.now.to_i)]))
    end
    
    # How many items in the queue?
    def length
      (@client.redis.pipelined do
        @client.redis.zcard("ql:q:" + @name + "-locks")
        @client.redis.zcard("ql:q:" + @name + "-work")
        @client.redis.zcard("ql:q:" + @name + "-scheduled")
      end).inject(0, :+)
    end
  end
end
