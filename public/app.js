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

function updateValues() {
  var index = _.sortedIndex(data, {timestamp: Date.timestamp() - 60}, 'timestamp')
  if (index > 0) {
    data.splice(0, index);
  }

  metrics = new Object();

  // Aggregate metrics
  $.each(data, function(k, item) {
    $.each(item, function(k,v) {
      if (metrics[k] === undefined) { metrics[k] = []; }
      metrics[k].push(v);
    });
  });

  $(".metric").each(function() {
    var type = $(this).data("type");
    var display = $(this).data("display");

    if (metrics[type] === undefined) {
      $(".data", this).text("No data")      
    } else {
      var value = window[display](metrics[type]);
      $(".data", this).text(value)      
    }
  });
}

function counter(items) {
  return items.length
}

function average(items) {
  var sum = 0;
  $.each(items, function() { sum += this })
  return sum/Math.max(items.length,1)
}

function median(items) {
  return "unimplemented"
}

function perc95(items) {
  return "unimplemented"
}