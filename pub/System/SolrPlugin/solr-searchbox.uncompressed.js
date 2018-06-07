"use strict";
jQuery(function($) {
  $(".solrSearchBox:not(.solrSearchBoxInited)").livequery(function() {
    var $this = $(this),
        extraFilter = $this.data("solrExtraFilter"),
        itemData = $this.data("solrItemData"),
	$form = $this.find("form:first"),
        action = $form.attr("action"),
        $input = $form.find("input[type=text]"),
        position = $.extend({
          my: "right top",
          at: "right bottom+11",
        }, {
          my: $form.data("position-my"),
          at: $form.data("position-at"),
        });

    $this.addClass("solrSearchBoxInited");

    $form.submit(function() {
      var search = $form.find("input[name='search']"),
          href = action + ((search && search.val())?'#q='+search.val():'');

      // TODO: add extraFilter to url
      window.location.href = href;
      return false;
    });

    if (typeof($.fn.autosuggest) === 'function') { // make sure autosuggest realy is present
      $input.autosuggest({
        extraParams: {
          filter: extraFilter
        },
        itemData: itemData,
        position: position,
        menuClass: 'natSearchBoxMenu',
        search: function() {
          $form.addClass("ui-autocomplete-busy");
        },
        response: function() {
          $form.removeClass("ui-autocomplete-busy");
        },
        open: function() {
          $form.removeClass("ui-autocomplete-busy");
        }
      });
    }
  });
});
