/*
 * Copyright (c) 2013-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
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

      // add extraFilter to url
      $.each(opts.solrExtraFilter, function(key, val) {
        href += '&'+encodeURIComponent(key+':'+val);
      });
      

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
