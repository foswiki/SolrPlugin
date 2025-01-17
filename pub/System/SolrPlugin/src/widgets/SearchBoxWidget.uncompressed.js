/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.SearchBoxWidget = AjaxSolr.AbstractTextWidget.extend({
    defaults: {
      instantSearch: false,
      instantSearchDelay: 750,
      instantSearchMinChars: 3
    },
    $input: null,
    timeoutID: null,

    afterRequest: function() {
      var self = this,
          q = self.manager.store.get("q");

      if (q && self.$input) {
        self.$input.val(q.val());
      }
    },

    autoSubmit: function() {
      var self = this;

      // clear an old one
      if (self.timeoutID) {
        window.clearTimeout(self.timeoutID);
	if (self.manager.xhr) {
	  self.manager.xhr.abort();
	}
      }

      // install a new one
      self.timeoutID = window.setTimeout(function() {
        self.$target.trigger("submit");
      }, self.options.instantSearchDelay);
    },
  
    init: function () {
      var self = this, search;

      self._super();
      self.$target = $(self.target);
      self.$input  = self.$target.find(".solrSearchField");
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());

      if (self.options.instantSearch) {
        self.$input.on("input", function(ev) {
          var val = self.$input.val().trim();
          if (!val.length || val.length >= self.options.instantSearchMinChars) {
            self.autoSubmit();
          }
        });
      } 

      self.$target.on("submit", function() {
        var val = self.$input.val();
        if (self.set(val)) {
          self.manager.doRequest(0);
        }
        return false;
      });
    }

  });

  AjaxSolr.Helpers.build("SearchBoxWidget");

})(jQuery);
