var data = [];
var metrics;
var will_extrapolate = true;

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

  updateValues();
}

var CURRENT_WINDOW_SIZE = 0;
var MAX_WINDOW_SIZE = 60;
var WINDOW_OFFSET = 10;

function updateValues() {
  var window_start = _.sortedIndex(data, {timestamp: Date.timestamp() - (MAX_WINDOW_SIZE + WINDOW_OFFSET + 1)}, 'timestamp')
  if (window_start > 0) {
    data.splice(0, window_start);
  }
  var window_end = _.sortedIndex(data, {timestamp: Date.timestamp() - (WINDOW_OFFSET)}, 'timestamp')
  var data_window = data.slice(0, window_end)
  if (data_window.length != 0) {
    CURRENT_WINDOW_SIZE = will_extrapolate ? Math.min(MAX_WINDOW_SIZE, Math.max(1, data_window[data_window.length - 1]['timestamp'] - data_window[0]['timestamp'])) 
                                           : MAX_WINDOW_SIZE;
  }

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
      $(this).addClass("loading")
    } else {
      $(this).removeClass("loading")
      var value = window[display](metrics[type], this);
    }
  });

  if (will_extrapolate && CURRENT_WINDOW_SIZE != MAX_WINDOW_SIZE) {
    $("#extraploated-legend .data").text(CURRENT_WINDOW_SIZE);
    $(".extrapolated").show();
  } else {
    will_extrapolate = false;
    $(".extrapolated").remove();
  }
}

function sum(items, elem) {
  var value = items.length;
  value = Math.round(value/(CURRENT_WINDOW_SIZE/MAX_WINDOW_SIZE))
  $(".data", elem).text(value + $(elem).data("label"))
}

function average(items, elem) {
  var value;
  var sum = 0;
  var units = $(elem).data("units") === undefined ? 1 : $(elem).data("units")

  $.each(items, function() { sum += this });
  value = Math.round(sum/Math.max(items.length,1)/units);
  $(".data", elem).text(value + $(elem).data("label"))
}

function counter(items, elem) {
  var container;
  var values = {}
  $.each($(elem).data("default"), function() { values[this] = 0 })

  $.each(items, function() {
    values[this] === undefined ? values[this] = 0 : null;
    values[this] += 1
  });

  container = $(".data", elem)
  container.empty()
  $.each(Object.keys(values).sort(), function(k,v) {
    container.append($("<li>" + v + ": " + values[v] + "</li>"))
  })
}

function utilization(items, elem) {
  var sum = 0;
  var utilization;
  $.each(items, function() { sum += this });

  utilization = ((sum/(CURRENT_WINDOW_SIZE * 1000 * $(elem).data("procs"))) * 100).toFixed(2)
  $(".data", elem).text(utilization + "%").css("width", utilization + "%")
}

function median(items, elem) {
  var value = percentile_index(items, 50);
  $(".data", elem).text(value + $(elem).data("label"))
}

function perc95(items, elem) {
  var value = percentile_index(items, 95);
  $(".data", elem).text(value + $(elem).data("label"))
}

function percentile_index(items, percentile) {
  percentile = percentile/100
  items.sort(function(a,b) { return a - b })
  return items[Math.ceil((Math.max(items.length - 1,0)) * percentile)]
}