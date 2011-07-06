class Select
	READ, WRITE, ERROR = 1, 2, 3

	attr_reader :read, :write, :error
	attr_accessor :exit, :exit_on_empty

	def empty?
		@read.empty? && @write.empty? && @error.empty?
	end

	def self.new *p, &e
		r = super *p
		if e
			e.call r
			r.close
		else r
		end
	end

	def initialize timeout = 30
		@read, @write, @error = {}, {}, {}
		@read.default = @write.default = @error.default = proc{}
		@timeout, @tevent, @exit, @exit_on_empty = timeout, proc{}, false, true
	end

	def timeout timeout = nil, &event
		return @timeout  if timeout.nil?
		raise ArgumentError, "Numeric value expected, not: '#{timeout}'"  unless timeout.kind_of? Numeric
		@timeout = timeout
		@tevent = event  if event
		timeout
	end

	def set hook, type = :read, &event
		raise ArgumentError, "This hook isn't supported: '#{hook.inspect}'"  unless hook.kind_of? IO
		raise ArgumentError, "Unexpected Event: '#{event.inspect}'"  unless event.kind_of? Proc
		case type
		when  READ, :read   then  @read[ hook] = event
		when WRITE, :write  then @write[ hook] = event
		when ERROR, :error  then @error[ hook] = event
		when nil
			@read[ hook] = event
			@write[ hook] = event
			@error[ hook] = event
		else raise ArgumentError, "Unknown event-type: '#{type}'"
		end
	end

	def del hook, type = nil
		case type
		when  READ, :read   then @read.delete hook
		when WRITE, :write  then @write.delete hook
		when ERROR, :error  then @error.delete hook
		when nil
			@read.delete hook
			@write.delete hook
			@error.delete hook
		else raise ArgumentError, "Unknown event-type: '#{type}'"
		end
	end

	def  read_set( hook, &event)  self.set hook,  :read, &event  end
	def write_set( hook, &event)  self.set hook, :write, &event  end
	def error_set( hook, &event)  self.set hook, :error, &event  end
	def  read_del( hook)   @read.delete hook  end
	def write_del( hook)  @write.delete hook  end
	def error_del( hook)  @error.delete hook  end

	def run_once timeout = @timeout
		r, w, e = Kernel.select( @read.keys, @write.keys, @error.keys, timeout)
		return @tevent.call  unless r or w or e
		r.each {|h|   @read[ h].call h, :read   }
		w.each {|h|  @write[ h].call h, :write  }
		e.each {|h|  @error[ h].call h, :error  }
	end

	def run &e
		if e
			until @exit || (@exit_on_empty && self.empty?)
				self.run_once
				e.call
			end
		else
			self.run_once  until @exit || (@exit_on_empty && self.empty?)
		end
	end
end

class Select::Buffer <String
	def inspect
		"#<Buffer:#{super}>"
	end

	def remove x
		self.slice! 0...x
	end
	alias remove! remove

	def each! x
		return Enumerator.new( self, :each!, x)  unless block_given?
		s = nil
		yield s  while s = self.slice!( x)
		self
	end

	def + s
		self.class.new super(s)
	end
end

class Select::Socket
	attr_reader :select, :sock, :bufsize, :parent

	def initialize opts
		self.init opts
		@select.read_set  @sock, &method( :event_read)
		@select.error_set @sock, &method( :event_error)
	end

	def init opts
		@select  = opts[ :select]  || Select.new
		@sock    = opts[ :sock]    || raise( ArgumentError, "need sock")
		@bufsize = opts[ :bufsize] || 4096
		@parent  = opts[ :parent]  || nil
		self.delimiter = opts[ :delimiter] || $/
		@linebuf, @writebuf = Select::Buffer.new(""), Select::Buffer.new("")
	end

	def delimiter= delimiter
		@delimiter = case delimiter
			when Regexp          then Regexp.new "^.*?"+delimiter.source
			when Fixnum, Bignum  then /^.{#{delimiter}}/
			else Regexp.new "^.*?"+Regexp.quote( delimiter.to_s)
			end
	end

	def write str
		e = @writebuf.empty?
		@writebuf += str
		@select.write_set @sock, &method( :event_write)  if e
	end
	alias :print :write
	alias :<< :write
	
	def puts str
		self.write "#{str}\n"
	end

	def close
		@select.del @sock
		@sock.close
		@parent.event_client_closed self  if @parent.respond_to? :event_client_closed
	rescue IOError
	end

	def event_line line
	end

	def event_read sock = @sock, event = :read
		@linebuf += sock.readpartial @bufsize
		@linebuf.each! @delimiter, &self.method( :event_line)
	rescue EOFError
		self.event_eof sock
	rescue Errno::EPIPE => e
		self.event_errno e, sock, event
	rescue IOError
		self.event_ioerror sock, event
	rescue Errno::ECONNRESET => e
		self.event_errno e, sock, event
	end

	def event_write sock = @sock, event = :write
		@writebuf.remove! sock.syswrite( @writebuf)
		@select.write_del sock  if @writebuf.empty?
		@writebuf
	rescue IOError
		@select.del @sock
		@writebuf
	end

	def event_eof sock = @sock
		self.close
	end

	def event_errno errno, sock = @sock, event = :error
		self.close
	end

	def event_error sock = @sock, event = :error
		self.close
	end

	def event_ioerror sock = @sock, event = :error
	end

	def closed?
		@sock.closed?
	end
end

class Select::Server
	attr_reader :select, :clientclass

	def initialize opts
		raise "You can't use this class directly. Create a subclass"  if self.class.superclass == Object
		init opts
		select.read_set @sock, &self.method( :event_conn)
	end

	def init opts
		@sock = opts[ :sock] || raise( ArgumentError, "need sock")
		@select = opts[ :select] || Select.new
		@clientclass = opts[ :clientclass] || Select::Socket
		@clients = []
	end

	def run
		@select.run
	end

	def delete sock
		@select.del sock
	end

	def event_conn sock = @sock, event = :read
		a = sock.accept
		c = event_new_client a
		if c.kind_of? Hash
			cc = c[ :clientclass] || @clientclass
			h = { :sock => a, :select => @select, :parent => self }.update c
			c = cc.new h
		end
		@clients.push c
	end

	def event_error sock = @sock, event = :error
	end

	def event_new_client sock
		Hash.new
	end

	def event_client_closed client
		@clients.delete client
	end

	def close
		@select.del @sock
		@sock.close
	rescue IOError
	end

	def clients_close
		@clients.each {|c| c.close }
	end
end
