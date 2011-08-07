$(document).ready(function() {
  $('.expandolink').toggle(function(event) {
    var expandoLink = $(this);
    var codeBlock = expandoLink.closest('pre');
    codeBlock.data('originalWidth', codeBlock.width());
    codeBlock.animate({width: 1000},
      {complete: function() { expandoLink.html("&lt;"); }}
    );
  },
  function(event) {
    var expandoLink = $(this);
    var codeBlock = expandoLink.closest('pre');
    codeBlock.animate({width: codeBlock.data('originalWidth')},
      {complete: function() { expandoLink.html("&gt;"); }}
    );
  }
  );
});

$(window).load(function() {
  $('.expandolink').each(function() {
    var expandoLink = $(this);
    var codeBlock = expandoLink.closest('pre');
    var hasOverflow = (codeBlock[0].scrollWidth > codeBlock.outerWidth());
    if ( !hasOverflow ) { expandoLink.hide(); }
  });
});
