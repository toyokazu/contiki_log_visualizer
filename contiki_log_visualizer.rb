#!/usr/bin/env ruby

require 'time'
require 'numo/gnuplot'

class LogParser

  def self.get_time(time_str)
    Time.parse("2018-01-01T00:" + time_str + "+00:00")
  end
  
  START = self.get_time("00:00.000")

  def self.get_ms(ms_str)
    ms_str.to_f / 1000
  end

  attr_reader :num_nodes, :nodes

  def initialize(num_nodes)
    @num_nodes = num_nodes
    @nodes = []
    num_nodes.times do |i|
      @nodes[i] = {
        handshake: {value: [], time: []},
        connect: {value: [], time: []},
        register: {value: [], time: []},
        subscribe: {value: [], time: []},
        recv_subscribe: {value: [], time: []},
        publish: {value: [], time: []},
        cpu: {value: [], time: []},
        lpm: {value: [], time: []},
        radio: {value: [], time: []},
        radio_tx: {value: [], time: []},
        radio_listen: {value: [], time: []},
        radio_message: {tx: [], rx: [], time: []}
      }
    end
  end

  def parse_event(event)
    node_id = event[:node_id].to_i - 1
    #node_id = event[2].to_i - 1
    message = event[:message]
    #message = event[3]
    timestamp = LogParser.get_time(event[:timestamp])
    #timestamp = LogParser.get_time(event[1])
    type = case message
    when /\[MQTT-SN\][^@]+@CONNECT/
      :connect
    when /\[MQTT-SN\][^@]+@REGISTER/
      :register
    when /\[MQTT-SN\][^@]+@SUBSCRIBE/
      :subscribe
    when /\[MQTT-SN\][^@]+@RECV_SUBSCRIBE/
      :recv_subscribe
    when /\[MQTT-SN\][^@]+@PUBLISH/
      :publish
    else
      return
    end
    @nodes[node_id][type][:value] << 0
    @nodes[node_id][type][:time] << (timestamp - START)
  end

  def handle_negative(value, integer, decimal)
    if decimal.to_f < 0
      integer.to_i - decimal.to_f
    else
      value.to_f
    end
  end

  def parse_powertrace(powertrace)
    node_id = powertrace[:node_id].to_i - 1
    #node_id = powertrace[2].to_i - 1
    timestamp = LogParser.get_time(powertrace[:timestamp])
    @nodes[node_id][:cpu][:value] << powertrace[:cpu].to_i
    @nodes[node_id][:lpm][:value] << powertrace[:lpm].to_i
    @nodes[node_id][:radio][:value] << handle_negative(powertrace[:radio], powertrace[:radio_integer], powertrace[:radio_decimal])
    @nodes[node_id][:radio_tx][:value] << handle_negative(powertrace[:radio_tx], powertrace[:radio_tx_integer], powertrace[:radio_tx_decimal])
    @nodes[node_id][:radio_listen][:value] << handle_negative(powertrace[:listen], powertrace[:listen_integer], powertrace[:listen_decimal])
    #@nodes[node_id][:cpu][:value] << powertrace[13].to_i
    #@nodes[node_id][:lpm][:value] << powertrace[14].to_i
    #@nodes[node_id][:radio][:value] << powertrace[20].to_f
    #@nodes[node_id][:radio_tx][:value] << powertrace[22].to_f
    #@nodes[node_id][:radio_listen][:value] << powertrace[24].to_f
    [:cpu, :lpm, :radio, :radio_tx, :radio_listen].each do |key|
      @nodes[node_id][key][:time] << (timestamp - START)
    end
  end

  def parse_powertrace_file(file)
    File.foreach(file) do |line|
      powertrace = line.match(/(?<timestamp>\d\d:\d\d\.\d+)\s+ID:(?<node_id>\d+)\s+(?<message>[^\$]+)\s*\$\$PT\$\$\s*(?<clock_time>\d+)\s+P\s+(?<linkaddr>\d+\.\d+)\s+(?<seq_no>\d+)\s+(?<all_cpu>\d+)\s+(?<all_lpm>\d+)\s+(?<all_transmit>\d+)\s+(?<all_listen>\d+)\s+(?<all_idle_transmit>\d+)\s+(?<all_idle_listen>\d+)\s+(?<cpu>\d+)\s+(?<lpm>\d+)\s+(?<transmit>\d+)\s+(?<listen>\d+)\s+(?<idle_transmit>\d+)\s+(?<idle_listen>\d+)\s+\(radio\s+(?<radio_all>(?<radio_all_integer>\d+)\.(?<radio_all_decimal>-*\d+))%\s+\/\s+(?<radio>(?<radio_integer>\d+)\.(?<radio_decimal>-*\d+))%\s+tx\s+(?<radio_tx_all>(?<radio_tx_all_integer>\d+)\.(?<radio_tx_all_decimal>-*\d+))%\s+\/\s+(?<radio_tx>(?<radio_tx_integer>\d+)\.(?<radio_tx_decimal>-*\d+))%\s+listen\s+(?<listen_all>(?<listen_all_integer>\d+)\.(?<listen_all_decimal>-*\d+))%\s+\/\s+(?<listen>(?<listen_integer>\d+)\.(?<listen_decimal>-*\d+))%\)\s*\$\$PT\$\$/)
      if powertrace.nil?
        event = line.match(/(?<timestamp>\d\d:\d\d\.\d+)\s+ID:(?<node_id>\d+)\s+(?<message>[^\$]+)\s*/)
        parse_event(event)
        next
      end
      parse_event(powertrace)
      parse_powertrace(powertrace)
    end
  end

  def init_next_radio_status
    @nodes.each do |node|
      if node[:radio_message][:tx][@cursor].nil?
        node[:radio_message][:tx][@cursor] = {}
        node[:radio_message][:rx][@cursor] = {}
        node[:radio_message][:time][@cursor] = @cursor * @interval + @interval / 2.0
      end
    end
  end

  def add_message(node_id, direction, type, message)
    label = "#{type}:#{message}"
    if @nodes[node_id - 1][:radio_message][direction][@cursor][label].nil?
      @nodes[node_id - 1][:radio_message][direction][@cursor][label] = 1
    else
      @nodes[node_id - 1][:radio_message][direction][@cursor][label] += 1
    end
  end
  
  def parse_radio_message(radio_message)
    type = radio_message[6]
    message = (radio_message[6] == 'D') ? radio_message[10] : "ACK"
    src_id = radio_message[2].to_i
    add_message(src_id, :tx, type, message)
    if radio_message[3] == '-'
      # TODO: The meaning of '-' is not clear yet. It should be investigated
      # currently, it is treated as sent but lost packet.
      #@nodes.size.times do |node_id|
      #  add_message(node_id, :rx, type, message)
      #end
    else
      dst_id = radio_message[3].to_i
      add_message(dst_id, :rx, type, message)
    end
  end

  def parse_radio_file(file)
    @cursor = 0 
    @interval = 0.100
    init_next_radio_status
    File.foreach(file) do |line|
      radio_message = line.match(/(\d+)\s+([\d\-]+)\s+([\d\-]+)\s+(\d+):\s+(\d+\.\d+)\s+([DA])\s+[^\|]+\|((IPHC\|IPv6)|(IPv6))\|([^\|]+)/)
      if radio_message.nil?
        radio_message = line.match(/(\d+)\s+([\d\-]+)\s+([\d\-]+)\s+(\d+):\s+(\d+\.\d+)\s+([DA])/)
      end
      while (@cursor + 1) * @interval < LogParser.get_ms(radio_message[1])
        @cursor += 1
        init_next_radio_status
      end
      parse_radio_message(radio_message)
    end
  end

  def self.message_filter(messages, filter_array = nil)
    if filter_array.nil?
      return messages.values.sum
    end
    filter_array.map do |key|
      messages[key].nil? ? 0 : messages[key]
    end.sum
  end

  def visualize_radio_message(node_id, filter_array = nil)
    node = @nodes[node_id - 1]
    Numo.gnuplot do
      set title: "radio message of node id: #{node_id}"
      plot *([
        [node[:radio_message][:time], node[:radio_message][:tx].map {|v| LogParser.message_filter(v, filter_array)}, {w: :lp, t: "tx"}],
        [node[:radio_message][:time], node[:radio_message][:rx].map {|v| LogParser.message_filter(v, filter_array)}, {w: :lp, t: "rx"}]
      ])
    end
  end

  def visualize_rdc(node_id)
    node = @nodes[node_id - 1]
    Numo.gnuplot do
      set title: "powertrace of node id: #{node_id}"
      plot *([:radio, :radio_tx, :radio_listen].map {|key|
        [node[key][:time], node[key][:value], {w: :lp, t: key.to_s.gsub('_', ' ')}]
      } + [:connect, :register, :subscribe, :recv_subscribe, :publish].map {|key|
        [node[key][:time], node[key][:value], {t: key.to_s.gsub('_', ' ')}]
      })
    end
  end

  def visualize_node(node_id, attr_filter = nil, mqtt_event_filter = nil, radio_filter = nil, radio_message = true)
    node = @nodes[node_id - 1]
    attr_filter ||= [:cpu, :lpm, :radio, :radio_tx, :radio_listen]
    mqtt_event_filter ||= [:connect, :register, :subscribe, :recv_subscribe, :publish]
    Numo.gnuplot do
      set title: "powertrace of node id: #{node_id}"
      set yrange: "[0 to 10000]"
      plot *(
        attr_filter.map {|key|
          [node[key][:time], node[key][:value], {w: :lp, t: key.to_s.gsub('_', ' ')}]
        } + mqtt_event_filter.map {|key|
          [node[key][:time], node[key][:value], {t: key.to_s.gsub('_', ' ')}]
        } + ((radio_message == false) ? [] : [
          [node[:radio_message][:time], node[:radio_message][:tx].map {|v| LogParser.message_filter(v, radio_filter)}, {w: :lp, t: "tx"}],
          [node[:radio_message][:time], node[:radio_message][:rx].map {|v| LogParser.message_filter(v, radio_filter)}, {w: :lp, t: "rx"}]
        ]))
    end
  end
end

@mqtt_sn = LogParser.new(2)
@mqtt_sn.parse_powertrace_file("./sample_data/mqtt_sn/mote-output.txt")
@mqtt_sn.parse_radio_file("./sample_data/mqtt_sn/radio-messages.txt")

@mqtt_sn_dtls = LogParser.new(2)
@mqtt_sn_dtls.parse_powertrace_file("./sample_data/mqtt_sn_dtls/mote-output.txt")
@mqtt_sn_dtls.parse_radio_file("./sample_data/mqtt_sn_dtls/radio-messages.txt")
