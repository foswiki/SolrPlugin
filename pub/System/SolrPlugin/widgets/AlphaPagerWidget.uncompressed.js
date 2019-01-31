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

  AjaxSolr.AlphaPagerWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    defaults:  {
      allText: 'All',
      union: true,
      title: "alpha",
      exclusion: true,
      enableScroll: false,
      scrollTarget: '.solrPager:first',
      scrollSpeed: 250
    },

    getCurrentVal: function() {
      var self = this, 
          value, match, field,
          fq = self.manager.store.values('fq');

      for (var i = 0, l = fq.length; i < l; i++) {
        match = fq[i].match(/^(?:{!.*?})?(.*?):(.*)$/);
        field = match[1];
        value = match[2]; 
        
        if (field === self.field) {
          return value;
        }
      }

      return;
    },

    afterRequest: function () {
      var self = this,
          currentVal = self.getCurrentVal() || '',
          marker;

      self.$target.empty();
      self.facetCounts = self.getFacetCounts();

      marker = currentVal?'':'current';
      $("<a href='#' class='"+marker+"'>"+self.options.allText+"</a>").click(self.unclickHandler(currentVal)).appendTo(self.$target);

      $.each(self.facetCounts.sort(function(a, b) {
          var facA = a.facet.toUpperCase(),
              facB = b.facet.toUpperCase();
          if (facA < facB) {
            return -1;
          }
          if (facA > facB) {
            return 1;
          }
          return 0;
      }), function(i, item) {
        marker = currentVal == item.facet ? 'current':'';
        $("<a href='#' class='"+marker+"'>"+item.facet+"</a>").on("click", self.clickHandler(item.facet)).appendTo(self.$target);
      });
    },

    init: function() {
      var self = this;

      self._super();
      AjaxSolr.Dicts["default"].set(self.field, self.options.title);
    }
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("AlphaPagerWidget");

})(jQuery);
