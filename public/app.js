function streamLogs(app, elem) {
  var source = new EventSource('/log/' + app);
  source.addEventListener('message', function(e) {
    line = $.parseJSON(e.data);

    $.each(line, function(k,v) {
      var elem = $(".metric." + k);
      var val = elem.data("value");
      var count;

      
      if (elem.hasClass("average")) {
        count = elem.data("count");
        count += 1;
        elem.data("count", count)

        val = ((val * (count-1)) + v)/count
      } else {
        val = val + v;
      }

      elem.data("value", val)
      $(".data", elem).text(val)
    })

  }, false);

  source.addEventListener('open', function(e) {
    // Conn open
  }, false);

  source.addEventListener('error', function(e) {
    if (e.eventPhase == EventSource.CLOSED) {
      // Connection was closed.
    }
  }, false);
}