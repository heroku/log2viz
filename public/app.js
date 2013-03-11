var data = [];
var metrics;

Date.timestamp = function() { return Math.round(Date.now()/1000); };

function streamLogs(app, elem) {
  var source = new EventSource('/log/' + app);
  var update = setInterval(function() { updateValues(); }, 1000);

  source.addEventListener('message', function(e) {
    var line = $.parseJSON(e.data);
    var index = _.sortedIndex(data, line, 'timestamp');
    data.splice(index, 0, line);
  }, false);

  source.addEventListener('open', function(e) {}, false); // Opened connection
  source.addEventListener('error', function(e) {
    if (e.eventPhase == EventSource.CLOSED) {
      console.log("closed connection");
      console.log(e);
    }
  }, false);
}

var WINDOW_SIZE = 60;
var WINDOW_OFFSET = 10;

function updateValues() {
  var window_start = _.sortedIndex(data, {timestamp: Date.timestamp() - (WINDOW_SIZE + WINDOW_OFFSET)}, 'timestamp')
  if (window_start > 0) {
    data.splice(0, window_start);
  }
  var window_end = _.sortedIndex(data, {timestamp: Date.timestamp() - (WINDOW_OFFSET)}, 'timestamp')
  var data_window = data.slice(0, window_end)

  metrics = new Object();

  // Aggregate metrics
  $.each(data_window, function(k, item) {
    $.each(item, function(k,v) {
      metrics[k] === undefined ? metrics[k] = [] : null;
      metrics[k].push(v);
    });
  });

  $(".metric").each(function() {
    var type = $(this).data("type");
    var display = $(this).data("display");

    if (metrics[type] === undefined) {
      $(".data", this).text("Calculating...")
    } else {
      var value = window[display](metrics[type], this);
      $(".data", this).text(value + " " + $(this).data("label"))
    }
  });
}

function sum(items) {
  return items.length;
}

function average(items, elem) {
  var sum = 0;
  var units = $(elem).data("units") === undefined ? 1 : $(elem).data("units")

  $.each(items, function() { sum += this });
  return Math.round(sum/Math.max(items.length,1)/units);
}

function counter(items) {

}

function median(items) {
  return "unimplemented"
}

function perc95(items) {
  return "unimplemented"
}