var data = [];
var metrics;
var graph;

Date.timestamp = function() { return Math.round(Date.now()/1000); };

function setupGraph() {
  graph = new Rickshaw.Graph( {
    element: document.getElementById("chart"),
    height: 125,
    renderer: 'line',
    series: new Rickshaw.Series.FixedDuration([{
      name: 'median_response_time'
    }], undefined, {
      timeInterval: 1000,
      maxDataPoints: 60,
      timeBase: new Date().getTime() / 1000
    })
  });
  new Rickshaw.Graph.HoverDetail({ graph: graph });
  graph.render();
}

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
      $(this).addClass("loading")
    } else {
      $(this).removeClass("loading")
      var value = window[display](metrics[type], this);
    }
  });

  var graphData = {};
  $(".graph_metrics li input:checked").each(function() {
    var parentElem = $(this).parent();
    var type = parentElem.data("type");
    var display = parentElem.data("display");
    var value = parentElem.data("value");

    if (metrics[type] === undefined) {
      $(this).addClass("loading")
    } else {
      $(this).removeClass("loading")
      graphData[$(this).attr("name")] = window[display](metrics[type], value);
    }
  });
  graph.series.addData(graphData);
  graph.render();
}

function sum(items, elem) {
  var value = items.length;
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

  utilization = ((sum/(WINDOW_SIZE * 1000 * $(elem).data("procs"))) * 100).toFixed(2)
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
