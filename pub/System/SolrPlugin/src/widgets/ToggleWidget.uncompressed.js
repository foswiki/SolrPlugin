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


