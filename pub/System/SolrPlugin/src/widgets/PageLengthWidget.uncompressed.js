/*
 * Copyright (c) 2022-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.PageLengthWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      rows: 20
    },

    update: function(rows) {
      var self = this;

      rows = rows || self.defaults.rows;
      //self.manager.store.get('rows').val(rows);
      self.manager.store.addByValue("rows", rows);
    },

    afterRequest: function() {
      var self = this, 
          rows = self.manager.store.get('rows').val();

      self.$target.find("option[value='"+rows+"']").prop("selected", true);
    },

    init: function() {
      var self = this;

      self._super();

      $.extend(self.defaults, self.$target.data());

      self.$target.find("select").on("change", function() {
        self.update($(this).val());
        self.manager.doRequest(0);
      });
    }
  });

  AjaxSolr.Helpers.build("PageLengthWidget");
})(jQuery);
