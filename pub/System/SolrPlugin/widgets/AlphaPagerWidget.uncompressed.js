(function ($) {
"use strict";

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
          val,
          fq = self.manager.store.values('fq');

console.log("fq=",fq);
      return val;
    },

    afterRequest: function () {
      var self = this,
          response = self.manager.response,
          responseHeader = response.responseHeader,
          currentVal = self.getCurrentVal(),
          lastVal = "Z";
      self.$target.empty();
      self.facetCounts = self.getFacetCounts();

      console.log("facetCounts=",self.facetCounts,"currentVal=",currentVal);

      $("<a href='#'>"+self.options.allText+"</a>").click(self.clickHandler()).appendTo(self.$target);

      $.each(self.facetCounts, function(i, item) {
        $("<a href='#' class=''>"+item.facet+"</a>").on("click", self.clickHandler(item.facet)).appendTo(self.$target);
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
