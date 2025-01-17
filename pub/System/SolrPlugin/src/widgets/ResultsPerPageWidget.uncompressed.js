/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {
  
  AjaxSolr.ResultsPerPageWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      templateName: '#solrResultsPerPageTemplate'
    },
    template: null,

    afterRequest: function() {
      var self = this,
          responseHeader = self.manager.response.responseHeader,
          rows = parseInt(self.manager.store.get('rows').val()),
          numFound = parseInt(self.manager.response.response.numFound),
          from = parseInt(responseHeader.params && responseHeader.params.start || 0),
          to = from+rows;

      if (to > numFound) {
        to = numFound;
      }

      self.$target.html(self.template.render({
        from: from+1,
        to: to,
        count: numFound
      }));
    },

    init: function () {
      var self = this;

      self._super();
      self.template = $.templates(self.options.templateName);
      if (!self.template) {
        throw "template "+self.options.templateName+" not found";
      }
    }
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("ResultsPerPageWidget");

})(jQuery);

