# IO-Management
# Fires if IO is ready a given block.
#
#   Select.open do |sel|
#     sock = TCPSocket.new 'localhost', 8090
#     buffer = ''
#
#     sel.on_read serv do |sock|
#				buffer << sock.sysread
#     end
#
#     sel.on_write STDOUT do |sock|
#       return  if buffer.empty?
#       written = sock.syswrite buffer
#       buffer = buffer[written..-1]
#     end
#
#     sel.on_error sock do |sock|
#			  sel.close
#     end
#   end

class Select
	READ, WRITE, ERROR = 1, 2, 3

	attr_reader :read, :write, :error
	attr_accessor :exit, :exit_on_empty

	# There are no events to wait?
	def empty?
		@read.empty? && @write.empty? && @error.empty?
	end

	class <<self
		# Creates a new Select-instance.
		# If you use a block, Select will close all IOs on end.
		def self.new *args, &exe
			r = super *args
			if exe
				yield r
				r.close
			else r
			end
		end
		alias open new
	end

	def initialize timeout = 30
		@read, @write, @error, @times = {}, {}, {}, []
		@read.default = @write.default = @error.default = proc{}
		@timeout, @tevent, @exit, @exit_on_empty = timeout, proc{}, false, true
		@pause = {read: {}, write: {}, error: {}}
	end

	def timeout timeout = nil, &event
		return @timeout  if timeout.nil?
		raise ArgumentError, "Numeric value expected, not: '#{timeout}'"  unless Numeric === timeout
		@timeout = timeout
		@tevent = event  if event
		timeout
	end

	def set io, type = :read, &event
		#raise ArgumentError, "This io isn't supported: '#{io.inspect}'"  unless IO === io
		#raise ArgumentError, "Unexpected Event: '#{event.inspect}'"  unless Proc === event
		case type
		when  READ, :read   then  @read[ io] = event
		when WRITE, :write  then @write[ io] = event
		when ERROR, :error  then @error[ io] = event
		when nil, :all
			@read[ io] = event
			@write[ io] = event
			@error[ io] = event
		else
			raise ArgumentError, "Unknown event-type: '#{type}'"
		end
	end
	alias on set

	def pause io, type = :read
		case type
		when  READ, :read   then @pause[ :read][  io] = @read.delete io
		when WRITE, :write  then @pause[ :write][ io] = @write.delete io
		when ERROR, :error  then @pause[ :error][ io] = @error.delete io
		when nil, :all
			@pause[ :read][ io] = @read.delete io
			@pause[ :write][ io] = @write.delete io
			@pause[ :error][ io] = @error.delete io
		else
			raise ArgumentError, "Unknown event-type: '#{type}'"
		end
	end

	def unpause io, type = :read
		case type
		when  READ, :read   then @read[  io] = @pause[ :read].delete io
		when WRITE, :write  then @write[ io] = @pause[ :write].delete io
		when ERROR, :error  then @error[ io] = @pause[ :error].delete io
		when nil, :all
			@read[  io] = @pause[ :read].delete io
			@write[ io] = @pause[ :write].delete io
			@error[ io] = @pause[ :error].delete io
		else
			raise ArgumentError, "Unknown event-type: '#{type}'"
		end
	end

	# Removes object from notification.
	# If type is read/write/error, only this, else all.
	def del io, type = nil
		case type
		when  READ, :read   then @read.delete io
		when WRITE, :write  then @write.delete io
		when ERROR, :error  then @error.delete io
		when nil, :all
			@read.delete io
			@write.delete io
			@error.delete io
		else
			raise ArgumentError, "Unknown event-type: '#{type}'"
		end
	end
	alias off del

	def  read_set( io, &event)  self.set io,  :read, &event  end
	def write_set( io, &event)  self.set io, :write, &event  end
	def error_set( io, &event)  self.set io, :error, &event  end
	def  read_del( io)   @read.delete io  end
	def write_del( io)  @write.delete io  end
	def error_del( io)  @error.delete io  end
	alias on_read read_set
	alias on_write write_set
	alias on_error error_set
	alias off_read read_del
	alias off_write write_del
	alias off_error error_del

	# only once this will be fired
	def one io, type = :read, &exe
		on io, type do |*args|
			off io, type
			yield *args
		end
	end

	# Runs once.
	# Every ready disposed to read/write or has an error, will be fired.
	def run_once timeout = nil
		timeout ||= @timeout
		r, w, e = Kernel.select( @read.keys, @write.keys, @error.keys, timeout)
		r and r.each {|h|   @read[ h].call h, :read   }
		w and w.each {|h|  @write[ h].call h, :write  }
		e and e.each {|h|  @error[ h].call h, :error  }
	end

	# Runs in a loop
	def run &e
		if e
			until @exit || (@exit_on_empty && empty?)
				cron
				self.run_once 1
				e.call
			end
		else
			until @exit || (@exit_on_empty && empty?)
				cron
				self.run_once 1
			end
		end
	end

	attr_reader :times
	def cron
		@times.each do |e|
			return if e > Time.now
			e.call
			@times.shift
		end
	end

	class Entry < Time
		attr_reader :do
		def do &e
			@do = e
		end

		def call *p
			@do.call *p
		end

		def self.new *a, &e
			x = self.at *a
			x.do &e
			x
		end
	end

	def at a, &e
		a = Entry.new a, &e if e
		@times << a
		@times.sort!
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

	def init sock: , delimiter: nil, select: nil, bufsize: nil, parent: nil
		@sock    = sock
		@select  = select  || Select.new
		@bufsize = bufsize || 4096
		@parent  = parent  || nil
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

	def init sock: , select: nil, clientclass: nil
		@sock = sock
		@select = select || Select.new
		@clientclass = clientclass || Select::Socket
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
