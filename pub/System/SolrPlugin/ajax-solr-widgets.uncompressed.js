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

      value = value.replace(/^(.*?):/, '');

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
          allFacetCounts = this._super();
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

      self._super();
    },

  });
})(jQuery);
(function ($) {

  AjaxSolr.FacetFieldWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    defaults: {
      templateName: '#solrFacetFieldTemplate',
      container: '.solrFacetFieldContainer',
      hideNullValues: true,
      hideSingle: true,
      name: null,
      dateFormat: null
    },
    facetType: 'facet_queries',
    template: null,
    container: null,
    paramString: null,
    inputType: null,

    initQueries: function() {
      var self = this;
      self.queries = $.parseJSON($(self.target).find(".solrJsonData").text());
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

      self.container.html($.tmpl(self.template, {
        widget: self
      }, {
        checked: function(facet) {
          return (self.isSelected(facet))?"checked='checked'":"";
        },
        getFacetValue: function(facet) {
          return self.getFacetValue(facet);
        },
        getFacetKey: function(facet) {
          return self.getFacetKey(facet);
        }
      }));
      self.$target.fadeIn();

      self.container.find("input[type='"+self.inputType+"']").change(function() {
        var $this = $(this), 
            title = $this.attr("title"),
            value = $this.val();
        
        if (self.facetType == 'facet_ranges') {
          value = value+' TO '+value+self["facet.range.gap"];
          if (title) {
            AjaxSolr.Dict['default'].set(value, title);
          }
          value = '['+value+']';
        }

        if ($this.is(":checked")) {
          self.clickHandler(value).call(self);
        } else {
          self.unclickHandler(value).call(self);
        }
      });
    },

    init: function() {
      var self = this;

      self.initQueries();

      self._super();
      self.template = $(self.options.templateName).template();
      self.container = self.$target.find(self.options.container);
      self.inputType = 'checkbox'; //(self.options.multiSelect)?'checkbox':'radio';
      self.$target.addClass("solrFacetContainer");
    }

  });

  AjaxSolr.Helpers.build("FacetFieldWidget");


})(jQuery);
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
        self.keyOfValue[facet] = facetCounts[i].key = _(facet.replace(/\./,"/"));
      }

      facetCounts.sort(function(a,b) {
        var aName = a.key.toLowerCase(), bName = b.key.toLowerCase();
        if (aName < bName) return -1;
        if (aName > bName) return 1;
        return 0;
      });

      return facetCounts;
    }

  });

  AjaxSolr.Helpers.build("WebFacetWidget");

})(jQuery);
(function ($) {

  AjaxSolr.ToggleFacetWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    options: {
      templateName: '#solrToggleFacetTemplate',
      value: null,
      inverse: false
    },
    checkbox: null,

    afterRequest: function () {
      var self = this;

      if (self.isSelected(self.options.value)) {
        if (self.options.inverse) {
          self.checkbox.removeAttr("checked");
        } else {
          self.checkbox.attr("checked", "checked");
        }
      } else {
        if (self.options.inverse) {
          self.checkbox.attr("checked", "checked");
        } else {
          self.checkbox.removeAttr("checked");
        }
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.$target.append($(self.options.templateName).tmpl({
        id: AjaxSolr.Helpers.getUniqueID(),
        title: self.options.title
      }));

      self.checkbox = 
        self.$target.find("input[type='checkbox']").change(function() {
          if ($(this).is(":checked")) {
            if (self.options.inverse) {
              self.unclickHandler(self.options.value).call(self);
            } else {
              self.clickHandler(self.options.value).call(self);
            }
          } else {
            if (self.options.inverse) {
              self.clickHandler(self.options.value).call(self);
            } else {
              self.unclickHandler(self.options.value).call(self);
            }
          }
        });

      if (self.options.inverse) {
        self.add(self.options.value);
      }
    }

  });

  AjaxSolr.Helpers.build("ToggleFacetWidget");


})(jQuery);


(function ($) {

  AjaxSolr.PagerWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults:  {
      prevText: 'Previous',
      nextText: 'Next',
      enableScroll: false,
      scrollSpeed: 250
    },

    clickHandler: function (page) {
      var self = this;
      return function () {
        var start = page * (self.manager.response.responseHeader.params && self.manager.response.responseHeader.params.rows || 20)
        //console.log("page=",page,"start="+start);
        //self.manager.store.get('start').val(start);
        self.manager.doRequest(start);
        if (self.options.enableScroll) {
          $.scrollTo(0, self.options.scrollSpeed);
        }
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
        $("<a href='#' class='solrPagerPrev'>"+self.options.prevText+"</a>").click(self.clickHandler(currentPage-1)).appendTo(self.$target);
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
        $("<a href='#'>1</a>").click(self.clickHandler(0)).appendTo(self.$target);
      }

      if (startPage > 1) {
        self.$target.append("<span class='solrPagerEllipsis'>&hellip;</span>");
      }

      count = 1;
      marker = '';
      for (var i = startPage; i <= endPage; i++) {
        marker = i == currentPage?'current':'';
        $("<a href='' class='"+marker+"'>"+(i+1)+"</a>").click(self.clickHandler(i)).appendTo(self.$target);
        count++;
      }

      if (endPage < lastPage-1) {
        self.$target.append("<span class='solrPagerEllipsis'>&hellip;</span>");
      }

      if (endPage < lastPage) {
        marker = currentPage == lastPage?'current':'';
        $("<a href='#' class='"+marker+"'>"+(lastPage+1)+"</a>").click(self.clickHandler(lastPage)).appendTo(self.$target);
      }

      if (currentPage < lastPage) {
        $("<a href='#' class='solrPagerNext'>"+self.options.nextText+"</a>").click(self.clickHandler(currentPage+1)).appendTo(self.$target);
      } else {
        self.$target.append("<span class='solrPagerNext foswikiGrayText'>"+self.options.nextText+"</span>");
      }
    },
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("PagerWidget");

})(jQuery);
(function ($) {
  
  AjaxSolr.ResultsPerPageWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      rows: 20,
      templateName: '#solrResultsPerPageTemplate'
    },
    template: null,

    afterRequest: function() {
      var self = this,
          rows = self.manager.store.get('rows').val(),
          responseHeader = self.manager.response.responseHeader,
          numFound = parseInt(self.manager.response.response.numFound),
          entriesPerPage = parseInt(responseHeader.params && responseHeader.params.rows || 20),
          from = parseInt(responseHeader.params && responseHeader.params.start || 0),
          to = from+entriesPerPage;

      if (to > numFound) {
        to = numFound;
      }

      self.$target.empty();

      self.$target.append($.tmpl(self.template, {
        from: from+1,
        to: to,
        count: numFound
      }));

      if (numFound > 0) {
        self.$target
          .find(".solrRows").show()
          .find("option[value='"+rows+"']").attr("selected", "selected")
          .end().find("select").change(function() {
            var rows = $(this).val();
            self.manager.store.get('rows').val(rows);
            self.manager.doRequest(0);
          });

      } else {
        self.$target.find(".solrRows").hide();
      }
    },

    init: function () {
      var self = this;

      self._super();
      self.template = $(self.options.templateName).template();
      if (!self.template) {
        throw "template "+self.options.templateName+" not found";
      }
    }
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("ResultsPerPageWidget");

})(jQuery);

(function ($) {

  AjaxSolr.ResultWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      blockUi: '#solrSearch',
      firstLoadingMessage:'Loading ...',
      loadingMessage: '',
      displayAs: '.solrDisplay',
      defaultDisplay: 'list',
      smallSize: 64,
      largeSize: 150,
      dateFormat: 'dddd, Do MMMM YYYY, LT',
      dictionary: 'default'
    },

    beforeRequest: function () {
      var self = this,
          pubUrlPath = foswiki.getPreference('PUBURLPATH'),
          systemWeb = foswiki.getPreference('SYSTEMWEB');

      if (self._isFirst) {
        $.blockUI({message:'<h1>'+_(self.options.firstLoadingMessage, self.options.dictionary)+'</h1>'});
      } else {
        $(self.options.blockUi).block({message:'<h1>'+_(self.options.loadingMessage, self.options.dictionary)+'</h1>'});
      }
    },

    getSnippet: function(data) {
      return data.text?data.text.substr(0, 300) + ' ...':'';
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

      self.$target.html($("#solrHitTemplate").tmpl(
        response.response.docs, {
          debug:function(msg) {
            //console.log(msg||'',this);
            return "";
          },
          getTemplateName: function() {
            var type = this.data.type, 
                topicType = this.data.field_TopicType_lst || [],
                templateName;

            if (type == 'topic') {
              for (var i = 0, l = topicType.length; i < l; i++) {
                templateName = "#solrHitTemplate_"+topicType[i];
                if ($(templateName).length) {
                  return templateName;
                }
              }
              return "#solrHitTemplate_topic";
            } 

            if (type.match(/png|gif|jpe?g|tiff|bmp/)) {
              return "#solrHitTemplate_image";
            } 

            return "#solrHitTemplate_misc";
          },
          renderList: function(fieldName, separator, limit) {
            var list = this.data[fieldName], result = '';

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
            var cats = this.data.field_Category_flat_lst, 
                tags = this.data.tag,
                lines, result = '';

            if (cats && cats.length) {
              result += _('Filed in', self.options.dictionary)+" ";
              lines = [];
              $.each(cats.sort().slice(0, 10), function(i, v) {
                lines.push(_(v, self.options.dictionary));
              });
              result += lines.join(", ");
              if (cats.length > 10) {
                result += " ...";
              }
            } 
            if (tags && tags.length) {
              if (cats && cats.length) {
                result += ", "+_("tagged", self.options.dictionary)+" ";
              } else {
                result += _("Tagged", self.options.dictionary)+" ";
              }
              result += tags.sort().slice(0, 10).join(", ");
              if (tags.length > 10) {
                result += " ...";
              }
            }

            return result;
          },
          getHilite: function(id) {
            var hilite;
            if (typeof(response.highlighting) === 'undefined') {
              return self.getSnippet(this.data)
            }
            hilite = response.highlighting[id];
            if (typeof(hilite) === 'undefined' || typeof(hilite.text) === 'undefined') {
              return self.getSnippet(this.data);
            } else {
              hilite = hilite.text.join(' ... ');
              return hilite || self.getSnippet(this.data);
            }
          },
          formatDate: function(dateString, dateFormat) {
            var oldFormat, result;

            if (dateString == '' || dateString == '0' || dateString == '1970-01-01T00:00:00Z') {
              return "???";
            }

            if (typeof(dateFormat) === 'undefined') {
              return moment(dateString).calendar();
            } 

            // hack it in temporarily ... jaul
            oldFormat = moment.calendar.sameElse;
            moment.calendar.sameElse = moment.calendar.lastWeek = dateFormat;
            result = moment(dateString).calendar();
            moment.calendar.sameElse = moment.calendar.lastWeek = oldFormat;
            
            return result;
          }
        }
      ));

      self.fixImageSize();
      self.$target.trigger("update");
    },

    fixImageSize: function() {
      var self = this, 
          elem = $(self.options.displayAs).filter(":checked"),
          size = (elem.val() == 'list')?self.options.smallSize:self.options.largeSize;

      self.$target.find(".solrImageFrame img").each(function() {
        var $this = $(this), src = $this.attr("src");
        $this.attr("src", src.replace(/size=(\d+)/, "size="+size)).attr("width", size);
      });
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
      self.fixImageSize();
    },

    init: function() {
      var self = this;

      self._super();
      $(self.options.displayAs).change(function() {
        self.update();
      });
      $(self.options.displayAs).filter("[value='"+self.options.defaultDisplay+"']").attr("checked", "checked");
      self._isFirst = true;

      self.update();

      // customize formatCalendar
      moment.calendar.sameElse = self.options.dateFormat;
      moment.calendar.lastWeek = self.options.dateFormat; // too funky for most users
      moment.longDateFormat.LT = 'HH:mm';
    }
  });


  AjaxSolr.Helpers.build("ResultWidget");

})(jQuery);
(function ($) {
  AjaxSolr.SearchBoxWidget = AjaxSolr.AbstractTextWidget.extend({
    defaults: {
      instantSearch: false,
      instantSearchDelay: 1000,
      instantSearchMinChars: 3
    },
    $input: null,
    doRequest: false,
    intervalID: null,

    afterRequest: function() {
      var self = this,
          q = self.manager.store.get("q");

      if (q && self.$input) {
        self.$input.val(q.val());
      }
    },

    installAutoSumbit: function() {
      var self = this;

      // clear an old one
      if (self.intervalID) {
        window.clearInterval(self.intervalID);
      }

      // install a new one
      self.intervalID = window.setInterval(function() {
        if (self.doRequest) {
          self.$target.submit();
        }
      }, self.options.instantSearchDelay);
    },
  
    init: function () {
      var self = this, search;

      self._super();
      self.$target = $(self.target);
      self.$input  = self.$target.find(".solrSearchField");
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());

      if (self.options.instantSearch) {
        self.installAutoSumbit();

        self.$input.bind("keydown", function() {
          self.installAutoSumbit();
          if (self.$input.val().length >= self.options.instantSearchMinChars) {
            self.doRequest = true;
          }
        });
      } 

      self.$target.submit(function() {
        var value = self.$input.val();
        if (self.set(value)) {
          self.doRequest = false;
          self.manager.doRequest(0);
        }
        return false;
      });
    }

  });

  AjaxSolr.Helpers.build("SearchBoxWidget");

})(jQuery);



(function ($) {

  AjaxSolr.CurrentSelectionWidget = AjaxSolr.AbstractJQueryWidget.extend({
    options: {
      defaultQuery: "",
      currentSelectionTemplate: "#solrCurrentSelectionTemplate",
      keywordText: "keyword"
    },
    selectionTemplate: null,
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
          self.doRequest(0);
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
      
      self.selectionContainer.append($.tmpl(self.selectionTemplate, {
        id: AjaxSolr.Helpers.getUniqueID(),
        field: _(field),
        facet: value
      }).change(handler));
    },

    removeFacet: function (field, value) {
      var self = this;

      return function() {
        if (self.manager.store.removeByValue('fq', field + ':' + AjaxSolr.Parameter.escapeValue(value))) {
          self.doRequest(0);
        }
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.selectionTemplate = $(self.options.currentSelectionTemplate).template();
      self.selectionContainer = self.$target.children("ul:first");
      self.$target.find(".solrClear").click(function() {
        self.clearSelection();
      });
    }
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("CurrentSelectionWidget");


})(jQuery);

(function ($) {
  AjaxSolr.SortWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      defaultSort: 'score desc'
    },

    update: function(value) {
      var self = this;

      if (value == 'score desc') { // default in solrconfig.xml
        self.manager.store.remove("sort");
      } else {
        self.manager.store.addByValue("sort", value);
      }
    },

    afterRequest: function() {
      var self = this, 
          currentSort = self.manager.store.get("sort");

      if (currentSort) {
        self.$target.find("option").removeAttr("selected");
        self.$target.find("[value='"+currentSort.val()+"']").attr('selected', 'selected');
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.$target.change(function() {
        self.update($(this).val());
        self.manager.doRequest(0);
      });
    }
    
  });

  AjaxSolr.Helpers.build("SortWidget");

})(jQuery);
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
        selectedValues[value] = true;
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
        self.$container.append($.tmpl(self.template, facetCounts));
        self.$container.find("a").click(function() {
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
      self.template = $(self.options.templateName).template();
      self.multivalue = true;
    }
  });

  AjaxSolr.Helpers.build("TagCloudWidget");

})(jQuery);

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
      
      self.$target.empty().append($.tmpl(self.template, {
        suggestions: self.suggestions
      }));

      //console.log("suggestions=",self.suggestions);

      self.$target.find("a").click(function() {
        self.manager.store.addByValue("q", $(this).text());
        self.manager.doRequest(0);
        return false;
      });
    },

    init: function() {
      var self = this;

      self.$target = $(self.target);
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());
      self.template = $(self.options.templateName).template();

      for (var name in self.options) {
        if (name.match(/^spellcheck/)) {
          self.manager.store.addByValue(name, self.options[name]);
        }
      }
    }
  });

  AjaxSolr.Helpers.build("SpellcheckWidget");

})(jQuery);


