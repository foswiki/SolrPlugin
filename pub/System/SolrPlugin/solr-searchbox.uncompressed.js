"use strict";
jQuery(function($) {
  $(".solrSearchBox:not(.solrSearchBoxInited)").livequery(function() {
    var $this = $(this),
        opts = $this.data(),
        $form = $this.find("form:first"),
        action = $form.attr("action"),
        $input = $form.find("input[type=text]"),
        position = $.extend({
          my: "right top",
          at: "right bottom+11",
        }, {
          my: opts.positionMy,
          at: opts.positionAt
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
          filter: opts.solrExtraFilter,
          groups: opts.groups
        },
        limits: {
          "global": opts.limit,
          "persons": opts.limitPersons,
          "topics": opts.limitTopics,
          "attachments": opts.limitAttachments,
        },
        itemData: opts.solrItemData,
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
