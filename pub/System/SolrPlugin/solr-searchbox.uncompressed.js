"use strict";
jQuery(function($) {
  $(".solrSearchBox form").livequery(function() {
    var $form = $(this),
        action = $form.attr("action"),
        $input = $form.find("input[type=text]"),
        position = $.extend({
          my: "right top",
          at: "right bottom+11",
        }, {
          my: $form.data("position-my"),
          at: $form.data("position-at"),
        });

    $form.submit(function() {
      var search = $form.find("input[name='search']"),
          href = action + ((search && search.val())?'#q='+search.val():'');
      window.location.href = href;
      return false;
    });

    if (typeof($.fn.autosuggest) === 'function') { // make sure autosuggest realy is present
      $input.autosuggest({
        position: position,
        menuClass: 'natSearchBoxMenu'
      });
    }
  });
});
