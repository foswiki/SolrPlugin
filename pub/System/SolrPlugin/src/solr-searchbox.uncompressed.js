/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
jQuery(function($) {
  $(".solrSearchBox").livequery(function() {
    var $this = $(this),
        opts = $this.data(),
        $form = $this.find("form:first"),
        action = $form.attr("action"),
        $input = $form.find(".foswikiInputField"),
        position = $.extend({
          my: "right top",
          at: "right bottom+11",
        }, {
          my: opts.positionMy,
          at: opts.positionAt
        });

    $form.on("submit", function() {
      var search = $form.find(".foswikiInputField"),
          term = search ? search.val() : '',
          href = action,
          origin = opts.origin || $form.find("input[name='origin']").val();


      if (origin) {
        href += "?origin="+origin;
      }

      href += "#";

      if (term !== '') {
        href += 'q='+encodeURIComponent(term.replace(/(^\s+)|(\s+$)/g, "")); /*.replace(/\*$/, ""))+'*';*/
      }

      // add extraFilter to url
      /* WTF
      $.each(opts.solrExtraFilter, function(key, val) {
        href += '&'+encodeURIComponent(key+':'+val);
      });*/
      
      window.location.href = href;
      return false;
    });

    if (typeof($.fn.autosuggest) === 'function') { // make sure autosuggest realy is present
      $input.autosuggest({
        extraParams: {
          queryfields: opts.solrQueryFields,
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
