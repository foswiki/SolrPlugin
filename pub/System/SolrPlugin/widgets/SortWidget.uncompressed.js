/*
 * Copyright (c) 2013-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.SortWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      defaultSort: 'score desc'
    },

    update: function(value) {
      var self = this;

      value = value || self.defaults.defaultSort;
      self.manager.store.addByValue("sort", value);
    },

    afterRequest: function() {
      var self = this, 
          currentSort = self.manager.store.get("sort"),
          val;

      if (currentSort) {
        val = currentSort.val();
      }
      val = val || self.defaults.defaultSort;
      self.$target.find("option").prop("selected", false);
      self.$target.find("[value='"+val+"']").prop('selected', true);
    },

    init: function() {
      var self = this, defaultSort;

      self._super();

      // hack
      $.extend(self.defaults, self.$target.data());
      defaultSort = self.defaults.defaultSort;
      if (defaultSort != "score desc") { // default in solrconfig.xml
        self.manager.store.addByValue("sort", self.defaults.defaultSort);
      }

      self.$target.change(function() {
        self.update($(this).val());
        self.manager.doRequest(0);
      });
    }
    
  });

  AjaxSolr.Helpers.build("SortWidget");

})(jQuery);
