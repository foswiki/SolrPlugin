/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {

  AjaxSolr.AbstractJQueryWidget = AjaxSolr.AbstractWidget.extend({
    defaults: {},
    options: {},
    $target: null,
    init: function() {
      var self = this;
      self.$target = $(self.target);
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());
    }
  });
})(jQuery);

