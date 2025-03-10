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

/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {

  AjaxSolr.AbstractJQueryFacetWidget = AjaxSolr.AbstractFacetWidget.extend({
    defaults: {
      facetType: 'facet_fields',
      facetMincount: 1,
      multiValue: false,
      union: false,
      exclusion: false,
      label: null,
      exclude: null,
      include: null,
      facetSortReverse: false
    },
    options: {},
    $target: null,
    facetCounts: [],

    isSelected: function(value) {
      var self = this,
          query = self.getQueryByKey(value);
      
      if (query) {
        value = query.value;
      }

      value = value.toString().replace(/^(.*?):/, '');

      return self.inQuery(value) >= 0;
    },

    getQueryByKey: function(key) {
      var self = this;

      if (self.queries) {
        for (var i = 0, l = self.queries.length; i < l; i++) {
          if (self.queries[i].key == key) {
            return self.queries[i];
          }
        }
      }

      return;
    },

    getQueryByValue: function(value) {
      var self = this;

      if (self.queries) {
        for (var i = 0, l = self.queries.length; i < l; i++) {
          if (self.queries[i].value == value) {
            return self.queries[i];
          }
        }
      }

      return;
    },

    getFacetCounts: function() {
      var self = this,
          allFacetCounts = this._super(),
          facetCounts = [];

      if (self.options.facetMincount == 0) {
        return allFacetCounts;
      }

      // filter never the less
      $.each(allFacetCounts, function(index, value) {
        if (
          value.count >= self.options.facetMincount && 
          (!self.options.exclude || !value.facet.match(self.options.exclude)) &&
          (!self.options.include || value.facet.match(self.options.include))
        ) {
          facetCounts.push(value);
        }
      });
      
      return (self.options.facetSortReverse?facetCounts.reverse():facetCounts);
    },

    init: function() {
      var self = this;

      self.$target = $(self.target);
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());
      self.facetType = self.options.facetType;

      // propagate some 
      self['facet.mincount'] = self.options.facetMincount;
      self['facet.sort'] = self.options.facetSort;
      self['facet.prefix'] = self.options.facetPrefix;
      self['facet.limit'] = self.options.facetLimit;
      self['facet.offset'] = self.options.facetOffset;
      self['facet.missing'] = self.options.facetMissing;
      self['facet.method'] = self.options.facetMethod;
      self['facet.enum.cache.minDf'] = self.options.facetEnumCacheMinDf;

      switch (self.facetType) {
        case 'facet_dates':
          self['facet.date.start'] = self.options.facetDateStart;
          self['facet.date.end'] = self.options.facetDateEnd;
          self['facet.date.gap'] = self.options.facetDateGap;
          self['facet.date.hardend'] = self.options.facetDateHardend;
          self['facet.date.other'] = self.options.facetDateOther;
          self['facet.date.include'] = self.options.facetDateInclude;
          break;
        case 'facet_ranges':
          self['facet.range.start'] = self.options.facetRangeStart;
          self['facet.range.end'] = self.options.facetRangeEnd;
          self['facet.range.gap'] = self.options.facetRangeGap;
          self['facet.range.hardend'] = self.options.facetRangeHardend;
          self['facet.range.other'] = self.options.facetRangeOther;
          self['facet.range.include'] = self.options.facetRangeInclude;
          break;
      }

      self.key = self.options.label;
      self.field = self.options.field;

      var param = self.manager.store.get("fl"),
          val = param.val();

      if (val == undefined) {
        param.val([self.field]);
      } else {
        val.push(self.field);
      }

      if (self.options.union) {
        self.multivalue = true;
        self.union = self.options.union;
      }

      if (self.options.multiValue) {
        self.tag = self.tag || self.field;
        self.multivalue = true;
      } else {
        self.multivalue = false;
      }

      if (self.options.exclusion) {
        self.tag = self.tag || self.field;
        self.ex = self.tag;
      }

      if (typeof(self.options.defaultValue) !== 'undefined') {
       var meth = self.multivalue ? (self.union ? 'append' : 'add') : 'set';
       self[meth].call(self, self.options.defaultValue);
      }

      self._super();
    }

  });
})(jQuery);
/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
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
    inputClass: null,

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

      self.$target.hide();

      if (self.facetCounts.length == 0) {
        return;
      } 

      if (this.options.hideSingle && self.facetCounts.length == 1) {
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

      self.container.find("input[type='"+self.inputType+"'], select").on("change", function() {
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

      self.$target.fadeIn();
    },

    init: function() {
      var self = this, timer;

      self.initQueries();

      self._super();
      self.template = $.templates(self.options.templateName);
      self.container = self.$target.find(self.options.container);
      self.filterField = self.$target.find(self.options.filterField);
      self.inputType = "checkbox";//(self.options.multiValue || self.options.union) ? 'checkbox' : 'radio';
      self.inputClass = (self.inputType === 'checkbox') ? 'foswikiCheckbox' : 'foswikiRadioButton';
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
/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {

  AjaxSolr.WebFacetWidget = AjaxSolr.FacetFieldWidget.extend({
    facetType: 'facet_fields',
    keyOfValue: {},

    getFacetKey: function(facet) {
      var self = this, key = self.keyOfValue[facet];
      return key?key:facet;
    },

    getFacetCounts: function() {
      var self = this,
          facetCounts = self._super(),
          facet;

      for (var i = 0, l = facetCounts.length; i < l; i++) {
        facet = facetCounts[i].facet;
        //self.keyOfValue[facet] = facetCounts[i].key = _(facet.slice(facet.lastIndexOf('.') + 1));
        self.keyOfValue[facet] = facetCounts[i].key = _(facet);
      }

      if (self.options.facetSort === 'title') {
        facetCounts.sort(function(a,b) {
          var aName = a.key.toLowerCase(), bName = b.key.toLowerCase();
          if (aName < bName) return -1;
          if (aName > bName) return 1;
          return 0;
        });
      } 

      return facetCounts;
    }

  });

  AjaxSolr.Helpers.build("WebFacetWidget");

})(jQuery);
/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.ToggleWidget = AjaxSolr.AbstractJQueryWidget.extend({
    options: {
      templateName: '#solrToggleTemplate',
      value: null,
      inverseValue: null,
      inverse: false
    },
    checkbox: null,

    remove: function (value) {
      var self = this;
      if (typeof(value) === 'undefined') {
        self.manager.store.remove(self.field);
      } else {
        self.manager.store.removeByValue(self.field, value);
      }
      return true;
    },
    add: function (value) {
      var self = this;
      return self.manager.store.add(self.field, new AjaxSolr.Parameter({ name: self.field, value: value}));
    },

    isSelected: function(value) {
      var self = this,
          found = false,
          res = self.manager.store.get(self.field);

      if (typeof(res) !== 'undefined') {

        if (AjaxSolr.isArray(res)) {
          for (var i = 0, l = res.length; i < l; i++) {
            if (res[i].val() === value) {
              found = true;
              break;
            }
          }
        } else {
          found = res.val() === value;
        }
      }

      return found;
    },

    afterRequest: function () {
      var self = this;

      if (self.isSelected(self.options.value)) {
        if (self.options.inverse) {
          self.checkbox.prop("checked", false);
        } else {
          self.checkbox.prop("checked", true);
        }
      } else {
        if (self.options.inverse) {
          self.checkbox.prop("checked", true);
        } else {
          self.checkbox.prop("checked", false);
        }
      }
    },

    clickHandler: function (value) {
      var self = this;

      return function () {
        if (self.add(value)) {
          self.doRequest(0);
        }
        return false;
      }
    },

    unclickHandler: function (value) {
      var self = this;

      return function () {
        if (self.remove(value)) {
          self.doRequest(0);
        }
        return false;
      }
    },

    init: function() {
      var self = this;

      self._super();

      self.$target.append($(self.options.templateName).render({
        id: AjaxSolr.Helpers.getUniqueID(),
        title: self.options.title
      }));

      self.checkbox = 
        self.$target.find("input[type='checkbox']").on("change", function() {
          if ($(this).is(":checked")) {
            if (self.options.inverse) {
              self.unclickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.clickHandler(self.options.inverseValue).call(self);
              }
            } else {
              self.clickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.unclickHandler(self.options.inverseValue).call(self);
              }
            }
          } else {
            if (self.options.inverse) {
              self.clickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.unclickHandler(self.options.inverseValue).call(self);
              }
            } else {
              self.unclickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.clickHandler(self.options.inverseValue).call(self);
              }
            }
          }
        });

      if (self.options.inverse) {
        self.add(self.options.value);
        if (self.options.inverseValue) {
          self.remove(self.options.inverseValue);
        }
      } else {
        if (self.options.inverseValue) {
          self.add(self.options.inverseValue);
        }
        self.remove(self.options.value);
      }
    }

  });

  AjaxSolr.Helpers.build("ToggleWidget");


})(jQuery);


/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.ToggleFacetWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    options: {
      templateName: '#solrToggleFacetTemplate',
      value: null,
      inverseValue: null,
      inverse: false,
      exclude: false,
      checked: undefined,
    },
    checkbox: null,

    afterRequest: function () {
      var self = this;

      if (self.isSelected(self.options.value)) {
        if (self.options.inverse || self._isExclude) {
          self.checkbox.prop("checked", false);
        } else {
          self.checkbox.prop("checked", true);
        }
      } else {
        if (self.options.inverse) {
          self.checkbox.prop("checked", true);
        } else {
          self.checkbox.prop("checked", false);
        }
      }
    },

    _updateValues: function(isChecked) {
        var self = this;

        self._isExclude = false;

        if (isChecked) {
          if (self.options.inverse) {
            self.remove(self.options.value);
            if (self.options.exclude) {
              self._isExclude = true;
              self.add(self.options.value, true);
            }
            if (self.options.inverseValue) {
              self.add(self.options.inverseValue);
            }
          } else {
            if (self.options.inverseValue) {
              self.remove(self.options.inverseValue);
            }
            if (self.options.exclude) {
              self.remove(self.options.value, true);
            }
            self.add(self.options.value);
          }
        } else {
          if (self.options.inverse) {
            self.add(self.options.value);
            if (self.options.exclude) {
              self.remove(self.options.value, true);
            }
            if (self.options.inverseValue) {
              self.remove(self.options.inverseValue);
            }
          } else {
            if (self.options.inverseValue) {
              self.add(self.options.inverseValue);
            }
            if (self.options.exclude) {
              self._isExclude = true;
              self.add(self.options.value, true);
            }
            self.remove(self.options.value);
          }
        }
    },

    init: function() {
      var self = this;

      self._super();

      self.$target.append($(self.options.templateName).render({
        id: AjaxSolr.Helpers.getUniqueID(),
        title: self.options.title
      }));

      self.checkbox = 
        self.$target.find("input[type='checkbox']").on("change", function() {
          self._updateValues($(this).is(":checked"));
          self.doRequest(0);
        });

      if (typeof(self.options.checked) !== 'undefined') {
        self._updateValues(self.options.checked);
      }
    }

  });

  AjaxSolr.Helpers.build("ToggleFacetWidget");


})(jQuery);


/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.PagerWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults:  {
      prevText: 'Previous',
      nextText: 'Next'
    },

    perPage: function () {
      return parseInt(this.manager.response.responseHeader && this.manager.response.responseHeader.params && this.manager.response.responseHeader.params.rows || this.manager.store.get('rows').val() || 10);
    },

    clickHandler: function (page) {
      var self = this;
      return function () {
        var start = page * self.perPage();
        //console.log("page=",page,"start=",start);
        //self.manager.store.get('start').val(start);
        self.manager.doRequest(start);
        return false;
      }
    },

    afterRequest: function () {
      var self = this,
          response = self.manager.response,
          responseHeader = response.responseHeader,
          entriesPerPage = parseInt(responseHeader.params && responseHeader.params.rows || 20),
          totalEntries = parseInt(response.response.numFound),
          start = parseInt(responseHeader.params && responseHeader.params.start || 0),
          startPage,
          endPage,
          currentPage,
          lastPage,
          count,
          marker;

      self.$target.empty();

      //console.log("responseHeader=",responseHeader, "totalEntries=",totalEntries);

      lastPage = Math.ceil(totalEntries / entriesPerPage) - 1;
      //console.log("lastPage=",lastPage);
      if (lastPage <= 0) {
        self.$target.hide();
        return;
      }
      self.$target.show();

      currentPage = Math.ceil(start / entriesPerPage);
      //console.log("currentPage=",currentPage,"lastPage=",lastPage);

      if (currentPage > 0) {
        $("<a href='#' class='solrPagerPrev'>"+self.options.prevText+"</a>").on("click", self.clickHandler(currentPage-1)).appendTo(self.$target);
      } else {
        self.$target.append("<span class='solrPagerPrev foswikiGrayText'>"+self.options.prevText+"</span>");
      }

      startPage = currentPage - 4;
      endPage = currentPage + 4;
      if (endPage >= lastPage) {
        startPage -= (endPage-lastPage+1);
        endPage = lastPage;
      }
      if (startPage < 0) {
        endPage -= startPage;
        startPage = 0;
      }
      if (endPage > lastPage) {
        endPage = lastPage;
      }

      if (startPage > 0) {
        $("<a href='#'>1</a>").on("click", self.clickHandler(0)).appendTo(self.$target);
      }

      if (startPage > 1) {
        self.$target.append("<span class='solrPagerEllipsis'>&hellip;</span>");
      }

      count = 1;
      marker = '';
      for (var i = startPage; i <= endPage; i++) {
        marker = i == currentPage?'current':'';
        $("<a href='' class='"+marker+"'>"+(i+1)+"</a>").on("click", self.clickHandler(i)).appendTo(self.$target);
        count++;
      }

      if (endPage < lastPage-1) {
        self.$target.append("<span class='solrPagerEllipsis'>&hellip;</span>");
      }

      if (endPage < lastPage) {
        marker = currentPage == lastPage?'current':'';
        $("<a href='#' class='"+marker+"'>"+(lastPage+1)+"</a>").on("click", self.clickHandler(lastPage)).appendTo(self.$target);
      }

      if (currentPage < lastPage) {
        $("<a href='#' class='solrPagerNext'>"+self.options.nextText+"</a>").on("click", self.clickHandler(currentPage+1)).appendTo(self.$target);
      } else {
        self.$target.append("<span class='solrPagerNext foswikiGrayText'>"+self.options.nextText+"</span>");
      }
    },
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("PagerWidget");

})(jQuery);
/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
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
      $("<a href='#' class='"+marker+"'>"+self.options.allText+"</a>").on("click", self.unclickHandler(currentVal)).appendTo(self.$target);

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

/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.ResultWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      maxHilite: 600,
      blockUi: '#solrSearch',
      firstLoadingMessage:'Loading ...',
      loadingMessage: '',
      displayAs: '.solrDisplay',
      defaultDisplay: 'list',
      dateFormat: 'dddd, Do MMMM YYYY, HH:mm',
      dictionary: 'default',
      enableScroll: true,
      scrollTarget: '.solrSearchHits',
      byteSuffix: ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB']
    },

    scrollIntoView: function() {
      var self = this,
          rect, elem;

      if (self.options.enableScroll) {
        elem = $(self.options.scrollTarget)[0];
        rect = elem.getBoundingClientRect();

        if (rect.top < 0) {
          elem.scrollIntoView({
            block: "start",
            inline: "nearest",
            behavior: "smooth"
          });
        }
      }
    },

    beforeRequest: function () {
      var self = this;

      if (self._isFirst) {
        $.blockUI({message:'<h1>'+_(self.options.firstLoadingMessage, self.options.dictionary)+'</h1>'});
      } else {
        $(self.options.blockUi).block({message:'<h1>'+_(self.options.loadingMessage, self.options.dictionary)+'</h1>'});
      }
    },

    // unused 
    getSnippet: function(data) {
      return data.text?data.text.substr(0, 300) + ' ...':'';
    },

    escapeHtml: function(text) {
      return $("<div />")
        .text(text)
        .html()
        .replace(/&lt;em&gt;/g, "<em>")
        .replace(/&lt;\/em&gt;/g, "</em>");
    },

    afterRequest: function () {
      var self = this,
          response = self.manager.response;

      //console.log("response=",response);
      if (self._isFirst) {
        self._isFirst = false;
        $.unblockUI();
      } else {
        $(self.options.blockUi).unblock();
      }

      if (!$("#solrSearch").is(":visible")) {
        $("#solrSearch").fadeIn();
      }

      // rewrite view urls
      $.each(response.response.docs, function(index,doc) {
        var containerWeb = doc.container_web,
            containerTopic = doc.container_topic;

        if (doc.type === "topic") {
          doc.url = foswiki.getScriptUrl("view", doc.web, doc.topic);
        }

        if (typeof(containerWeb) === 'undefined' || typeof(containerTopic) === 'undefined') {
          if (typeof(doc.container) !== 'undefined' && doc.container_id.match(/^(.*)\.(.*)$/)) {
            containerWeb = RegExp.$1;
            containerTopic = RegExp.$2;
          }
        }

        if (typeof(containerWeb) !== 'undefined' && typeof(containerTopic) !== 'undefined') {
          doc.container_url = foswiki.getScriptUrl("view", containerWeb, containerTopic);
        }
      });

      self.$target.html($("#solrHitTemplate").render(
        response.response.docs, {
          debug:function(msg) {
            console.log(msg||'',this);
            return "";
          },
          encodeURIComponent: function(text) {
            return encodeURIComponent(text);
          },
          getPubUrlPath: function(web, topic, file, params) {
            return foswiki.getPubUrlPath(web, topic, file, params);
          },
          getScriptUrlPath: function(script, web, topic, params) {
            return foswiki.getScriptUrlPath(script, web, topic, params);
          },
          getTemplateName: function() {
            var type,
                topicType = this.data.field_TopicType_lst || [],
                i, j, l, m,
                templateName;

            for (j = 0, m = this.data.type.length; j < m; j++) {
              type = this.data.type[j].replace(/%\d+/g, "");  // clean up errors in data

              if (type === 'file') {
                return "#solrHitTemplate_file";
              }

              for (i = 0, l = topicType.length; i < l; i++) {
                templateName = "#solrHitTemplate_"+topicType[i].replace(/[\s\(\)]+/g, "_");
                if ($(templateName).length) {
                  return templateName;
                }
              }

              if (type === 'topic') {
                return "#solrHitTemplate_topic";
              }

              if (type.match(/png|gif|jpe?g|tiff|bmp/)) {
                return "#solrHitTemplate_image";
              }

              templateName = "#solrHitTemplate_"+type;
              if ($(templateName).length) {
                 return templateName;
              }
            }

            return "#solrHitTemplate_misc";
          },
          renderList: function(fieldName, separator, limit) {
            var list = this.data[fieldName], result = '', lines;

            separator = separator || ', ';
            limit = limit || 10;

            if (list && list.length) {
              lines = [];
              $.each(list.sort().slice(0, limit), function(i, v) {
                lines.push(_(v, self.options.dictionary));
              });
              result += lines.join(separator);
              if (list.length > limit) {
                result += " ...";
              }
            }

            return result;
          },
          renderTopicInfo: function() {
            var data = this.data,
		cats = data.field_Category_link_lst,
                tags = data.tag,
                lines, result = '';

            if (cats && cats.length) {
              result += '<i class="fa fa-folder"></i>';
              lines = [];
              $.each(cats.sort().slice(0, 10), function(i, v) {
		lines.push(v);
              });
              result += lines.join(", ");
              if (cats.length > 10) {
                result += " ...";
              }
            }
            if (tags && tags.length) {
              if (cats && cats.length) {
                result += "<span class='solrSep'>&#124;</span>";
              }
              result += '<i class="fa fa-tag"></i>';
              result += tags.sort().slice(0, 10).join(", ");
              if (tags.length > 10) {
                result += " ...";
              }
            }

            return result;
          },
          getHilite: function(id) {
            var hilite, result = [];
            if (typeof(response.highlighting) === 'undefined') {
              return '';
            }
            hilite = response.highlighting[id];
            if (typeof(hilite) === 'undefined' || typeof(hilite.text) === 'undefined') {
              return '';
            } else {
              // manually truncate hilite results as solr doesnt seem to do the job using fragsize
              hilite.text.forEach(function(elem) {
                var text = self.escapeHtml(elem);
                result.push(text);
              });
              return result.join(' ... ');//.substring(0, self.options.maxHilite);
            }
          },
          getIcon: function(icon) {
            var cls = "solrHitIcon foswikiIcon jqIcon",
                match;

            icon = icon || "fa-file-o";

            if (icon.startsWith("http")) {
              return "<img src='"+icon+"' class='solrHitIcon' />";
            }

            if (match = icon.match(/^(.*?)\-/)) {
              cls += " " + match[1];
            }
            cls += " " + icon;

            return "<i class='"+cls+"'></i>";
          },
          formatDate: function(dateString, dateFormat) {

            // convert epoch seconds to iso date string
            if (/^\d+$/.test(dateString)) {
              if (dateString.length == 10) {
                dateString += "000";
              }
              dateString = (new Date(parseInt(dateString))).toISOString();
            }

            if (typeof(dateString) === 'undefined' || dateString == '' || dateString == '0' || dateString == '1970-01-01T00:00:00Z') {
              return "???";
            }

            return moment(dateString).format(dateFormat || self.options.dateFormat);
            //return moment(dateString).calendar();
          },
          formatBytes: function(num) {
            var magnitude = 0, suffix, len = self.options.byteSuffix.length,
                value = parseInt(num, 10);

            while (magnitude < len) {
              suffix = self.options.byteSuffix[magnitude];
              if (value < 1024) {
                break;
              }
              value = value / 1024;
              magnitude++;
            }
            value = Math.round(value * 100) / 100;
            return value + ' ' + suffix;
          },
          contains: function(arr, val) {
             return $.inArray(val, arr) >= 0;
          }
        }
      ));

      self.$target.trigger("update");
      self.scrollIntoView();
    },

    update: function() {
      var self = this,
          elem = $(self.options.displayAs).filter(":checked");

      self.$target.removeClass("solrSearchHitsList solrSearchHitsGrid");
      if ((self.options.defaultDisplay == 'list' && !elem.length) || elem.val() == 'list') {
        self.$target.addClass("solrSearchHitsList");
      } else {
        self.$target.addClass("solrSearchHitsGrid");
      }
    },

    init: function() {
      var self = this;

      self._super();
      $(self.options.displayAs).on("change", function() {
        self.update();
      });
      $(self.options.displayAs).filter("[value='"+self.options.defaultDisplay+"']").prop("checked", true);
      self._isFirst = true;

      self.update();
    }
  });


  AjaxSolr.Helpers.build("ResultWidget");

})(jQuery);
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
/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.CurrentSelectionWidget = AjaxSolr.AbstractJQueryWidget.extend({
    options: {
      defaultQuery: "",
      templateName: "#solrCurrentSelectionTemplate",
      keywordText: "keyword"
    },
    template: null,
    selectionContainer: null,

    getKeyOfValue: function(field, value) {
      var self = this, 
          key = value.replace(/^[\(\[]?(.*?)[\]\)]?$/, "$1"),
          responseParams = self.manager.response.responseHeader.params,
          facetTypes = ["facet.field", "facet.query", "facet.date"], //"facet.range"],
          //facetTypes = ["facet.query"],
          regex = /\s*([^=]+)='?([^'=]+)'?\s*/g, local, paramString, match;

      value = value.replace(/([\[\]\.\*\?\+\-\(\)])/g, "\\$1");

      for (var i in facetTypes) {
        for (var j in responseParams[facetTypes[i]]) {
          paramString = responseParams[facetTypes[i]][j];
          match = paramString.match("^{!(.*)}\\w+:"+value);
          if (match) {
            match = match[1];
            //console.log("match=",match);
            while ((local = regex.exec(match)) != null) {
              //console.log("local=",local[1],"=",local[2]);
              if (local[1] == 'key') {
                return local[2];
              }
            }
          }
        }
      }

      if (field == 'web') {
        var arr = key.split(/ /);
        for (var i = 0, l = arr.length; i < l; i++) {
          arr[i] = _(arr[i].replace(/\./g, '/'));
        }
        return arr.join(", ");
      }

      return _(key);
    },

    afterRequest: function () {
      var self = this, 
          fq = self.manager.store.values('fq'),
          q = self.manager.store.get('q').val(),
          match, field, value, key, count = 0;

      self.clearSelection();

      if (q && q !== self.options.defaultQuery) {
        count++;
        self.addSelection(self.options.keywordText, q, function() {
          self.manager.store.get('q').val(self.options.defaultQuery);
          self.manager.doRequest(0);
        });
      }

      for (var i = 0, l = fq.length; i < l; i++) {
        if (fq[i] && !self.manager.store.isHidden("fq="+fq[i])) {
          count++;
          match = fq[i].match(/^(?:{!.*?})?(.*?):(.*)$/);
          field = match[1];
          value = match[2]; 
          key = self.getKeyOfValue(field, value); 
          self.addSelection(field, key, self.removeFacet(field, value));
        }
      }

      if (count) {
        self.$target.find(".solrNoSelection").hide();
        self.$target.find(".solrClear").show();
      }
    },

    clearSelection: function()  {
      var self = this;
      self.selectionContainer.children().not(".solrNoSelection").remove();
      self.$target.find(".solrNoSelection").show();
        self.$target.find(".solrClear").hide();
    },

    addSelection: function(field, value, handler) {
      var self = this;

      if (field.match(/^([\-\+])/)) {
        field = field.substr(1);
        value = RegExp.$1 + value;
      }
      
      self.selectionContainer.append($(self.template.render({
        id: AjaxSolr.Helpers.getUniqueID(),
        field: _(field),
        facet: value
      })).on("change", handler));
    },

    removeFacet: function (field, value) {
      var self = this;

      return function() {
        if (self.manager.store.removeByValue('fq', field + ':' + AjaxSolr.Parameter.escapeValue(value))) {
          self.manager.doRequest(0);
        }
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.template = $.templates(self.options.templateName);
      self.selectionContainer = self.$target.children("ul:first");
      self.$target.find(".solrClear").on("click", function() {
        self.clearSelection();
      });
    }
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("CurrentSelectionWidget");


})(jQuery);

/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
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
      if (defaultSort !== "score desc") { // default in solrconfig.xml
        self.manager.store.addByValue("sort", self.defaults.defaultSort);
      }

      self.$target.on("change", function() {
        self.update($(this).val());
        self.manager.doRequest(0);
      });
    }
    
  });

  AjaxSolr.Helpers.build("SortWidget");

})(jQuery);
/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.TagCloudWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    defaults: {
      title: 'title not set',
      buckets: 20,
      offset: 11,
      container: ".solrTagCloudContainer",
      normalize: true,
      facetMincount: 1,
      facetLimit: 100,
      templateName: "#solrTagCloudTemplate",
      startColor: [ 104, 144, 184 ],
      endColor: [ 0, 102, 255 ]
    },
    $container: null,
    template: null,
    facetType: 'facet_fields',

    getFacetCounts: function() {
      var self = this, 
          facetCounts = self._super(),
          floor = -1, ceiling = 0, diff, incr = 1,
          selectedValues = {};

      $.each(self.getQueryValues(self.getParams()), function(index, value) {
        selectedValues[value.replace(/^"(.*)"$/, "$1")] = true;
      });
     
      // normalize, floor, ceiling
      $.each(facetCounts, function(index, value) {
        if (self.options.normalize) {
          value.normCount = Math.log(value.count);
        } else {
          value.normCount = value.count;
        }

        if (value.normCount > ceiling) {
          ceiling = value.normCount;
        }
        if (value.normCount < floor || floor < 0) {
          floor = value.normCount;
        }
      });
      
      // compute the weights and rgb
      diff = ceiling - floor;
      if (diff) {
        incr = diff / (self.options.buckets-1);
      } 
      
      // sort
      facetCounts.sort(function(a,b) {
        var aName = a.facet.toLowerCase(), bName = b.facet.toLowerCase();
        if (aName < bName) return -1;
        if (aName > bName) return 1;
        return 0;
      });

      var lastGroup = '';
      $.each(facetCounts, function(index, value) {
        var c = value.facet.substr(0,1).toUpperCase();
        value.weight = Math.round((value.normCount - floor)/incr)+self.options.offset+1;
        value.color = self.fadeRGB(value.weight);
        if (c == lastGroup) {
          value.group = '';
        } else {
          value.group = ' <strong>'+c+'</strong>&nbsp;';
          lastGroup = c;
        }
        value.current = selectedValues[value.facet]?'current':'';
      });

      return facetCounts;
    },

    fadeRGB: function(weight) {
      var self = this, 
          max = self.options.buckets + self.options.offset,
          red = Math.round(self.options.startColor[0] * (max-weight) / max + self.options.endColor[0] * weight / max),
          green = Math.round(self.options.startColor[1]*(max-weight)/max+self.options.endColor[1]*weight/max),
          blue = Math.round(self.options.startColor[2]*(max-weight)/max+self.options.endColor[2]*weight/max);

      return "rgb("+red+","+green+","+blue+")";
    },

    afterRequest: function() {
      var self = this, 
          facetCounts = self.getFacetCounts();

      if (facetCounts.length) {
        self.$target.show();
        self.$container.empty();
        self.$container.append(self.template.render(facetCounts));
        self.$container.find("a").on("click", function() {
          var $this = $(this),
              term = $(this).text();
          if ($this.is(".current")) {
            self.unclickHandler(term).apply(self);
          } else {
            self.clickHandler(term).apply(self);
          }
          return false;
        });
      } else {
        self.$target.hide();
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.$container = self.$target.find(self.options.container);
      self.template = $.templates(self.options.templateName);
      self.multivalue = true;
    }
  });

  AjaxSolr.Helpers.build("TagCloudWidget");

})(jQuery);

/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.HierarchyWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    defaults: {
      templateName: '#solrHierarchyTemplate',
      container: '.solrHierarchyContainer',
      breadcrumbs: '.solrHierarchyBreadcrumbsContainer',
      hideNullValues: false,
      hideSingle: false,
      name: null
    },

    updateHierarchy: function() {
      var self = this, dict;

      if (typeof(self.hierarchy) === 'undefined') {
        $.ajax({
          url: foswiki.getScriptUrl('rest', 'SolrPlugin', 'webHierarchy'),
          async: false,
          data: {
            //root:self.options.root, SMELL
            web:self.options.web
          },
          success: function(data) {
            self.hierarchy = data;
          }
        });

        dict = AjaxSolr.Dicts["default"];
        $.each(self.hierarchy, function(i, entry) {
          var id = entry.id, 
              title = entry.title,
              label = entry.id.split(/\s*\.\s*/).pop();
          dict.set(id, title);
          dict.set(label, title);
        });
      }

      
      return self.hierarchy;
    },

    getChildren: function(id) {
      var self = this, children = [];

      if (typeof(id) !== 'undefined') {
        if (typeof(self.hierarchy[id].children) !== 'undefined' && typeof(self.hierarchy[id]) !== 'undefined') {
          $.each(self.hierarchy[id].children, function(i, val) {
            var entry = self.hierarchy[val];
            if (!self.options.hideNullValues || self.facetCounts[val]) {// || entry.type == 'web') {
              children.push(entry);
            }
          });
        }
      } else {
        $.each(self.hierarchy, function(i, entry) {
          if (typeof(entry['parent']) === 'undefined' && (!self.options.hideNullValues || self.facetCounts[entry.id] || entry.type == 'web')) {
            children.push(entry);
          }
        });
      }

      return children.sort(function(a, b) {
        return (a.title < b.title ? -1 : (a.title > b.title ? 1 : 0));
      });
    },

    afterRequest: function () {
      var self = this, currrent, children = [], facetCounts = {}, breadcrumbs = [], prefix = [], current;

      self.$target.hide();
      self.facetCounts = self.getFacetCounts();

      if (typeof(self.facetCounts) === 'undefined' || self.facetCounts.length == 0) {
        return;
      } 

      $.each(self.facetCounts, function(i, entry) {
        facetCounts[entry.facet] = entry.count;
      });

      self.facetCounts = facetCounts;

      //console.log("facetCounts=",facetCounts);

      if (this.options.hideSingle && self.facetCounts.length == 1) {
        return;
      } 

      current = self.getQueryValues(self.getParams());
      if (typeof(current) === 'undefined') {
        return;
      }

      current = current[0];
      if (typeof(current) === 'undefined') {
        if (typeof(self.options.web) !== 'undefined') {
          current = self.options.web;
        }
        if (typeof(self.options.root) !== 'undefined') {
          current += '.' + self.options.root;
        }
      }

      self.breadcrumbs.empty();
      breadcrumbs.push("<a href='#' class='solrFacetValue root' data-value='"+current+"'>"+_("Root")+"</a>");
      if (typeof(current) !== 'undefined') {
        $.each(current.split(/\s*\.\s*/), function(i, val) {
          prefix.push(val);
          breadcrumbs.push("<a href='#' class='solrFacetValue' data-value='"+prefix.join(".")+"'>"+_(val)+"</a>");
        });
      }
      self.breadcrumbs.append(breadcrumbs.join("&nbsp;&#187; "));

      children = self.getChildren(current);
/*
      if (children.length == 0) {
        return;
      }
*/

      // okay lets do it
      self.$target.show();
      self.container.html(self.template.render(children, {
        renderFacetCount: function(facet) {
          var count = self.facetCounts[facet];
          return count?"<span class='solrHierarchyFacetCount'>("+count+")</span>":""; 
        },
        getCategory: function(id) {
          return self.hierarchy[id];
        },
        getChildren: function() {
          return self.getChildren(this.data.id);
        }
      }));

      if (typeof(current) !== 'undefined') {
        self.container.find("a.cat_"+current.replace(/\./g, "\\.")).addClass("current");
      }

      self.container.parent().find("a").on("click", function() {
        var $this = $(this),
            value = $(this).data("value");
        if ($this.is(".root")) {
          self.unclickHandler(value).apply(self);
        } else {
          self.clickHandler(value).apply(self);
        }
        return false;
      });

    },

    init: function() {
      var self = this;

      self._super();
      self.template = $.templates(self.options.templateName);
      self.container = self.$target.find(self.options.container);
      self.breadcrumbs = self.$target.find(self.options.breadcrumbs);
      self.updateHierarchy();

    }

  });

  AjaxSolr.Helpers.build("HierarchyWidget");


})(jQuery);
/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.SpellcheckWidget = AjaxSolr.AbstractSpellcheckWidget.extend({
    defaults: {
      "spellcheck": true,
      "spellcheck.count": 3,
      "spellcheck.collate": true,
      "spellcheck.onlyMorePopular": false,
      "spellcheck.maxCollations": 3,
      "spellcheck.maxCollationTries": 10,
      //"spellcheck.extendedResults": true,
      "templateName": "#solrSpellCorrectionTemplate"
    },
    options: {},
    $target: null,
    template: null,

    beforeRequest: function() {
      var self = this;

      self._super();

      self.$target.empty();
    },

    handleSuggestions: function() {
      var self = this;
      
      self.$target.html(self.template.render({
        suggestions: self.suggestions
      }));

      //console.log("suggestions=",self.suggestions);

      self.$target.find("a").on("click", function() {
        self.manager.store.addByValue("q", $(this).text());
        self.manager.doRequest(0);
        return false;
      });
    },

    init: function() {
      var self = this;

      self.$target = $(self.target);
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());
      self.template = $.templates(self.options.templateName);

      for (var name in self.options) {
        if (name.match(/^spellcheck/)) {
          self.manager.store.addByValue(name, self.options[name]);
        }
      }
    }
  });

  AjaxSolr.Helpers.build("SpellcheckWidget");

})(jQuery);


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
