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

  AjaxSolr.FacetFieldWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    defaults: {
      templateName: '#solrFacetFieldTemplate',
      container: '.solrFacetFieldContainer',
      filterField: '.solrFacetFieldFilter>input',
      hideNullValues: true,
      hideSingle: true,
      name: null,
      dateFormat: null
    },
    facetType: 'facet_queries',
    template: null,
    container: null,
    filterField: null,
    paramString: null,
    inputType: null,

    initQueries: function() {
      var self = this, text = $(self.target).find(".solrJsonData").text();
      if (text) {
        self.queries = $.parseJSON(text);
      }
    },

    getFacetValue: function(facet) {
      var self = this, query = self.getQueryByKey(facet);
      return (query && query.value)?query.value:facet;
    },

    getFacetKey: function(facet) {
      var self = this, query;

      if (this.options.dateFormat) {
        // SMELL: dependency on jquery.ui.datepicker
        return $.datepicker.formatDate(this.options.dateFormat, new Date(facet));
      }
      
      query = self.getQueryByValue(facet);
      return (query && query.key)?query.key:_(facet);
    },

    afterRequest: function () {
      var self = this,
          thisParamString = self.manager.store.string().replace(/&?start=\d*/g, "");

      // init
      if (self.paramString == thisParamString) {
        return; // no need to render the widget again; just paging
      }

      self.paramString = thisParamString;
      self.facetCounts = self.getFacetCounts();

      if (self.facetCounts.length == 0) {
        self.$target.hide();
        return;
      } 

      if (this.options.hideSingle && self.facetCounts.length == 1) {
        self.$target.hide();
        return;
      } 

      self.container.html(self.template.render({
        widget: self
      }, {
        checked: function(facet) {
          return (self.isSelected(facet))?"checked='checked'":"";
        },
        selected: function(facet) {
          return (self.isSelected(facet))?"selected='selected'":"";
        },
        getFacetValue: function(facet) {
          return self.getFacetValue(facet);
        },
        getFacetKey: function(facet) {
          return self.getFacetKey(facet);
        }
      }));
      self.$target.fadeIn();

      self.container.find("input[type='"+self.inputType+"'], select").change(function() {
        var $this = $(this), 
            title = $this.attr("title"),
            value = $this.val();
        
        if (self.facetType == 'facet_ranges') {
          value = value+' TO '+value+self["facet.range.gap"];
          if (title) {
            AjaxSolr.Dicts['default'].set(value, title);
          }
          value = '['+value+']';
        }

        if (value == '') {
          self.clear();
          self.manager.doRequest(0);
        } else {
          if ($this.is(":checked, select")) {
            self.clickHandler(value).call(self);
          } else {
            self.unclickHandler(value).call(self);
          }
        }
      });

      if (self.filterField && self.filterField.is(":visible")) {
        var val = self.filterField.val();
        if (typeof(val) !== 'undefined') {
          self.container.find(".jqSerialPager").data("filter", val);
        }
      }

      self.$target.children("h2").each(function() {
        var text = $(this).text();
        if (text) {
          AjaxSolr.Dicts['default'].set(self.field,text);
        }
      });
    },

    init: function() {
      var self = this, timer;

      self.initQueries();

      self._super();
      self.template = $.templates(self.options.templateName);
      self.container = self.$target.find(self.options.container);
      self.filterField = self.$target.find(self.options.filterField);
      self.inputType = 'checkbox'; //(self.options.multiSelect)?'checkbox':'radio';
      self.$target.addClass("solrFacetContainer");

      self.$target.find(".solrFacetFieldTwisty").on("afterClose.twisty", function() {
        var val = self.filterField.val();
        if (typeof(val) !== 'undefined') {
          self.container.find(".jqSerialPager").trigger("refresh");
        }
        self.filterField.blur();
      }).on("afterOpen.twisty", function() {
        var val = self.filterField.val();
        if (typeof(val) !== 'undefined') {
          self.container.find(".jqSerialPager").trigger("refresh", val);
        }
        self.filterField.focus();
      });

      self.filterField.on("keyup", function(ev) {
        var $input = $(this),
            val = $input.val(),
            pager = self.container.find(".jqSerialPager");

        if (pager.length) {
          if (typeof(timer) !== 'undefined') {
            clearTimeout(timer);
            timer = undefined;
          }
          timer = window.setTimeout(function() {
            pager.trigger("refresh", val);
            timer = undefined;
          }, 250);
        }
      });

    }

  });

  AjaxSolr.Helpers.build("FacetFieldWidget");


})(jQuery);
