# Wavefront Direct Ingestion Client.
# Sends data directly to Wavefront cluster via the direct ingestion API.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require 'uri'
require 'net/http'

require_relative '../../entities/metrics/wavefront_metric_sender'
require_relative '../../entities/histogram/wavefront_histogram_sender'
require_relative '../../entities/tracing/wavefront_tracing_span_sender'
require_relative '../../common/utils'

class WavefrontDirectClient
  include WavefrontMetricSender
  include WavefrontHistogramSender
  include WavefrontTracingSpanSender

  WAVEFRONT_METRIC_FORMAT = 'wavefront'
  WAVEFRONT_HISTOGRAM_FORMAT = 'histogram'
  WAVEFRONT_TRACING_SPAN_FORMAT = 'trace'

  attr_reader :WAVEFRONT_METRIC_FORMAT, :WAVEFRONT_HISTOGRAM_FORMAT, :WAVEFRONT_TRACING_SPAN_FORMAT,
              :server, :token, :max_queue_size, :batch_size, :flush_interval_seconds

  attr_accessor :metrics_buffer, :histograms_buffer, :tracing_spans_buffer, :headers

  # Construct Direct Client.
  #
  # @param server [String] Server address, Example: https://INSTANCE.wavefront.com
  # @param token [String] Token with Direct Data Ingestion permission granted
  # @param max_queue_size [Integer] Max Queue Size, size of internal data buffer for each data type, 50000 by default.
  # @param batch_size [Integer] Batch Size, amount of data sent by one api call, 10000 by default
  # @param flush_interval_seconds [Integer] Interval flush time, 5 secs by default
  def initialize(server, token, max_queue_size=50000, batch_size=10000, flush_interval_seconds=5)
    @server = server
    @token = token
    @max_queue_size = max_queue_size
    @batch_size = batch_size
    @flush_interval_seconds = flush_interval_seconds
    @default_source = "wavefrontDirectSender"
    @metrics_buffer = SizedQueue.new(max_queue_size)
    @histograms_buffer = SizedQueue.new(max_queue_size)
    @tracing_spans_buffer = SizedQueue.new(max_queue_size)
    @headers = {'Content-Type'=>'application/octet-stream',
                     'Content-Encoding'=>'gzip',
                     'Authorization'=>'Bearer ' + token}
    @closed = false
    #@schedule_lock = Lock()
    #@timer = None
    #@schedule_timer()
  end

  # One api call sending one given string data.

  # @param points [List<String>] List of data in string format, concat by '\n'
  # @param data_format [String] Type of data to be sent
  def report(points, data_format)
    begin
      payload = WavefrontUtil.gzip_compress(points)
      uri = URI.parse(server)
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      request = Net::HTTP::Post.new('/report', headers)
      request['f'] = data_format
      request.body = payload

      response = https.request(request)
      unless [200, 202].include? response.code.to_i
        puts "Error reporting points, Response #{response.code} #{response.message}"
      end
    rescue Exception => error
      #increment_failure_count()
      raise error
    end
  end

  # One api call sending one given list of data.
  #
  # @param batch_line_data [List] List of data to be sent
  # @param data_format [String] Type of data to be sent
  def batch_report(batch_line_data, data_format)
    # Split data into chunks, each with the size of given batch_size
    data_chunks = WavefrontUtil.chunks(batch_line_data, batch_size)
    data_chunks.each do |batch|
      # report once per batch
      report(batch.join("\n") + "\n", data_format)
    end
  end

  # Send Metric Data via direct ingestion API.
  #
  # Wavefront Metrics Data format
  #   <metricName> <metricValue> [<timestamp>] source=<source> [pointTags]
  #
  # Example
  #   'new-york.power.usage 42422 1533531013 source=localhost
  #   datacenter=dc1'
  #
  # @param name [String] Metric Name
  # @param value [Float] Metric Value
  # @param timestamp [Long] Timestamp
  # @param source [String] Source
  # @param tags [Hash] Tags
  def send_metric(name, value, timestamp, source, tags)
    line_data = WavefrontUtil.metric_to_line_data(name, value, timestamp, source, tags, default_source)
    metrics_buffer.push(line_data)
  end

  # Send a list of metrics immediately.
  #
  # Have to construct the data manually by calling
  # common.utils.metric_to_line_data()
  # @param metrics [List<String>] List of string spans data
  def send_metric_now(metrics)
    batch_report(metrics, WAVEFRONT_METRIC_FORMAT)
  end

  # Send a list of distribution immediately.
  #
  # Have to construct the data manually by calling
  # common.utils.histogram_to_line_data()
  #
  # @param distributions [List<String>] List of string spans data
  def send_distribution_now(distributions)
    batch_report(distributions, WAVEFRONT_HISTOGRAM_FORMAT)
  end

  # Send a list of spans immediately.
  #
  # Have to construct the data manually by calling
  # common.utils.tracing_span_to_line_data()
  #
  # @param spans [List<String>] List of string spans data
  def send_span_now(spans)
    batch_report(spans, WAVEFRONT_TRACING_SPAN_FORMAT)
  end
end