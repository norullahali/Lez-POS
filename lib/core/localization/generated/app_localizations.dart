import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_ku.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('ku')
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'ليز POS'**
  String get appName;

  /// No description provided for @ok.
  ///
  /// In ar, this message translates to:
  /// **'موافق'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @add.
  ///
  /// In ar, this message translates to:
  /// **'إضافة'**
  String get add;

  /// No description provided for @search.
  ///
  /// In ar, this message translates to:
  /// **'بحث'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In ar, this message translates to:
  /// **'تصفية'**
  String get filter;

  /// No description provided for @close.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد'**
  String get confirm;

  /// No description provided for @yes.
  ///
  /// In ar, this message translates to:
  /// **'نعم'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In ar, this message translates to:
  /// **'لا'**
  String get no;

  /// No description provided for @loading.
  ///
  /// In ar, this message translates to:
  /// **'جاري التحميل...'**
  String get loading;

  /// No description provided for @noData.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد بيانات'**
  String get noData;

  /// No description provided for @error.
  ///
  /// In ar, this message translates to:
  /// **'خطأ'**
  String get error;

  /// No description provided for @success.
  ///
  /// In ar, this message translates to:
  /// **'تم بنجاح'**
  String get success;

  /// No description provided for @required.
  ///
  /// In ar, this message translates to:
  /// **'مطلوب'**
  String get required;

  /// No description provided for @optional.
  ///
  /// In ar, this message translates to:
  /// **'اختياري'**
  String get optional;

  /// No description provided for @all.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get all;

  /// No description provided for @active.
  ///
  /// In ar, this message translates to:
  /// **'نشط'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In ar, this message translates to:
  /// **'غير نشط'**
  String get inactive;

  /// No description provided for @currency.
  ///
  /// In ar, this message translates to:
  /// **'د.ع'**
  String get currency;

  /// No description provided for @qty.
  ///
  /// In ar, this message translates to:
  /// **'الكمية'**
  String get qty;

  /// No description provided for @price.
  ///
  /// In ar, this message translates to:
  /// **'السعر'**
  String get price;

  /// No description provided for @total.
  ///
  /// In ar, this message translates to:
  /// **'المجموع'**
  String get total;

  /// No description provided for @discount.
  ///
  /// In ar, this message translates to:
  /// **'الخصم'**
  String get discount;

  /// No description provided for @subtotal.
  ///
  /// In ar, this message translates to:
  /// **'المجموع الفرعي'**
  String get subtotal;

  /// No description provided for @notes.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات'**
  String get notes;

  /// No description provided for @date.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get date;

  /// No description provided for @from.
  ///
  /// In ar, this message translates to:
  /// **'من'**
  String get from;

  /// No description provided for @to.
  ///
  /// In ar, this message translates to:
  /// **'إلى'**
  String get to;

  /// No description provided for @print.
  ///
  /// In ar, this message translates to:
  /// **'طباعة'**
  String get print;

  /// No description provided for @export.
  ///
  /// In ar, this message translates to:
  /// **'تصدير'**
  String get export;

  /// No description provided for @name.
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get name;

  /// No description provided for @description.
  ///
  /// In ar, this message translates to:
  /// **'الوصف'**
  String get description;

  /// No description provided for @phone.
  ///
  /// In ar, this message translates to:
  /// **'الهاتف'**
  String get phone;

  /// No description provided for @address.
  ///
  /// In ar, this message translates to:
  /// **'العنوان'**
  String get address;

  /// No description provided for @barcode.
  ///
  /// In ar, this message translates to:
  /// **'الباركود'**
  String get barcode;

  /// No description provided for @unit.
  ///
  /// In ar, this message translates to:
  /// **'الوحدة'**
  String get unit;

  /// No description provided for @category.
  ///
  /// In ar, this message translates to:
  /// **'الفئة'**
  String get category;

  /// No description provided for @supplier.
  ///
  /// In ar, this message translates to:
  /// **'المورد'**
  String get supplier;

  /// No description provided for @status.
  ///
  /// In ar, this message translates to:
  /// **'الحالة'**
  String get status;

  /// No description provided for @nav_dashboard.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get nav_dashboard;

  /// No description provided for @nav_pos.
  ///
  /// In ar, this message translates to:
  /// **'نقطة البيع'**
  String get nav_pos;

  /// No description provided for @nav_products.
  ///
  /// In ar, this message translates to:
  /// **'المنتجات'**
  String get nav_products;

  /// No description provided for @nav_categories.
  ///
  /// In ar, this message translates to:
  /// **'الفئات'**
  String get nav_categories;

  /// No description provided for @nav_suppliers.
  ///
  /// In ar, this message translates to:
  /// **'الموردون'**
  String get nav_suppliers;

  /// No description provided for @nav_purchases.
  ///
  /// In ar, this message translates to:
  /// **'المشتريات'**
  String get nav_purchases;

  /// No description provided for @nav_opening_stock.
  ///
  /// In ar, this message translates to:
  /// **'الرصيد الافتتاحي'**
  String get nav_opening_stock;

  /// No description provided for @nav_inventory.
  ///
  /// In ar, this message translates to:
  /// **'المخزن'**
  String get nav_inventory;

  /// No description provided for @nav_returns.
  ///
  /// In ar, this message translates to:
  /// **'المرتجعات'**
  String get nav_returns;

  /// No description provided for @nav_reports.
  ///
  /// In ar, this message translates to:
  /// **'التقارير'**
  String get nav_reports;

  /// No description provided for @nav_settings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get nav_settings;

  /// No description provided for @dashboard_title.
  ///
  /// In ar, this message translates to:
  /// **'لوحة التحكم'**
  String get dashboard_title;

  /// No description provided for @dashboard_today_sales.
  ///
  /// In ar, this message translates to:
  /// **'مبيعات اليوم'**
  String get dashboard_today_sales;

  /// No description provided for @dashboard_invoice_count.
  ///
  /// In ar, this message translates to:
  /// **'عدد الفواتير'**
  String get dashboard_invoice_count;

  /// No description provided for @dashboard_today_profit.
  ///
  /// In ar, this message translates to:
  /// **'أرباح اليوم'**
  String get dashboard_today_profit;

  /// No description provided for @dashboard_low_stock.
  ///
  /// In ar, this message translates to:
  /// **'منتجات نفدت'**
  String get dashboard_low_stock;

  /// No description provided for @dashboard_expiring.
  ///
  /// In ar, this message translates to:
  /// **'منتجات قاربت على الانتهاء'**
  String get dashboard_expiring;

  /// No description provided for @dashboard_top_products.
  ///
  /// In ar, this message translates to:
  /// **'أكثر المنتجات مبيعاً'**
  String get dashboard_top_products;

  /// No description provided for @dashboard_no_alerts.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تنبيهات'**
  String get dashboard_no_alerts;

  /// No description provided for @pos_title.
  ///
  /// In ar, this message translates to:
  /// **'نقطة البيع'**
  String get pos_title;

  /// No description provided for @pos_open_session.
  ///
  /// In ar, this message translates to:
  /// **'فتح جلسة الكاشير'**
  String get pos_open_session;

  /// No description provided for @pos_close_session.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق الجلسة'**
  String get pos_close_session;

  /// No description provided for @pos_cashier_name.
  ///
  /// In ar, this message translates to:
  /// **'اسم الكاشير'**
  String get pos_cashier_name;

  /// No description provided for @pos_opening_cash.
  ///
  /// In ar, this message translates to:
  /// **'النقد الافتتاحي'**
  String get pos_opening_cash;

  /// No description provided for @pos_search_product.
  ///
  /// In ar, this message translates to:
  /// **'ابحث أو امسح الباركود...'**
  String get pos_search_product;

  /// No description provided for @pos_cart_empty.
  ///
  /// In ar, this message translates to:
  /// **'العربة فارغة'**
  String get pos_cart_empty;

  /// No description provided for @pos_cart_title.
  ///
  /// In ar, this message translates to:
  /// **'العربة'**
  String get pos_cart_title;

  /// No description provided for @pos_checkout.
  ///
  /// In ar, this message translates to:
  /// **'الدفع'**
  String get pos_checkout;

  /// No description provided for @pos_payment.
  ///
  /// In ar, this message translates to:
  /// **'طريقة الدفع'**
  String get pos_payment;

  /// No description provided for @pos_cash.
  ///
  /// In ar, this message translates to:
  /// **'نقدي'**
  String get pos_cash;

  /// No description provided for @pos_card.
  ///
  /// In ar, this message translates to:
  /// **'بطاقة'**
  String get pos_card;

  /// No description provided for @pos_mixed.
  ///
  /// In ar, this message translates to:
  /// **'مختلط'**
  String get pos_mixed;

  /// No description provided for @pos_amount_paid.
  ///
  /// In ar, this message translates to:
  /// **'المبلغ المدفوع'**
  String get pos_amount_paid;

  /// No description provided for @pos_change.
  ///
  /// In ar, this message translates to:
  /// **'الباقي'**
  String get pos_change;

  /// No description provided for @pos_confirm_payment.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الدفع'**
  String get pos_confirm_payment;

  /// No description provided for @pos_receipt.
  ///
  /// In ar, this message translates to:
  /// **'إيصال'**
  String get pos_receipt;

  /// No description provided for @pos_new_sale.
  ///
  /// In ar, this message translates to:
  /// **'بيع جديد'**
  String get pos_new_sale;

  /// No description provided for @pos_session_summary.
  ///
  /// In ar, this message translates to:
  /// **'ملخص الجلسة'**
  String get pos_session_summary;

  /// No description provided for @pos_invoice_discount.
  ///
  /// In ar, this message translates to:
  /// **'خصم الفاتورة'**
  String get pos_invoice_discount;

  /// No description provided for @pos_item_discount.
  ///
  /// In ar, this message translates to:
  /// **'خصم البند'**
  String get pos_item_discount;

  /// No description provided for @pos_insufficient_stock.
  ///
  /// In ar, this message translates to:
  /// **'المخزون غير كافٍ'**
  String get pos_insufficient_stock;

  /// No description provided for @pos_product_not_found.
  ///
  /// In ar, this message translates to:
  /// **'المنتج غير موجود'**
  String get pos_product_not_found;

  /// No description provided for @pos_session_closed.
  ///
  /// In ar, this message translates to:
  /// **'الجلسة مغلقة'**
  String get pos_session_closed;

  /// No description provided for @pos_open_first.
  ///
  /// In ar, this message translates to:
  /// **'افتح جلسة أولاً'**
  String get pos_open_first;

  /// No description provided for @pos_closing_cash.
  ///
  /// In ar, this message translates to:
  /// **'النقد الختامي'**
  String get pos_closing_cash;

  /// No description provided for @pos_total_sales.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المبيعات'**
  String get pos_total_sales;

  /// No description provided for @pos_total_invoices.
  ///
  /// In ar, this message translates to:
  /// **'عدد الفواتير'**
  String get pos_total_invoices;

  /// No description provided for @pos_session_cash.
  ///
  /// In ar, this message translates to:
  /// **'نقدي'**
  String get pos_session_cash;

  /// No description provided for @pos_session_card.
  ///
  /// In ar, this message translates to:
  /// **'بطاقة'**
  String get pos_session_card;

  /// No description provided for @pos_keyboard_hint.
  ///
  /// In ar, this message translates to:
  /// **'F2: بحث | F12: دفع | Esc: مسح'**
  String get pos_keyboard_hint;

  /// No description provided for @products_title.
  ///
  /// In ar, this message translates to:
  /// **'المنتجات'**
  String get products_title;

  /// No description provided for @products_add.
  ///
  /// In ar, this message translates to:
  /// **'إضافة منتج'**
  String get products_add;

  /// No description provided for @products_edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل منتج'**
  String get products_edit;

  /// No description provided for @products_name.
  ///
  /// In ar, this message translates to:
  /// **'اسم المنتج'**
  String get products_name;

  /// No description provided for @products_barcode.
  ///
  /// In ar, this message translates to:
  /// **'الباركود'**
  String get products_barcode;

  /// No description provided for @products_cost_price.
  ///
  /// In ar, this message translates to:
  /// **'سعر التكلفة'**
  String get products_cost_price;

  /// No description provided for @products_sell_price.
  ///
  /// In ar, this message translates to:
  /// **'سعر البيع'**
  String get products_sell_price;

  /// No description provided for @products_wholesale_price.
  ///
  /// In ar, this message translates to:
  /// **'سعر الجملة'**
  String get products_wholesale_price;

  /// No description provided for @products_unit.
  ///
  /// In ar, this message translates to:
  /// **'وحدة القياس'**
  String get products_unit;

  /// No description provided for @products_min_stock.
  ///
  /// In ar, this message translates to:
  /// **'حد التنبيه (أدنى مخزون)'**
  String get products_min_stock;

  /// No description provided for @products_track_expiry.
  ///
  /// In ar, this message translates to:
  /// **'تتبع تاريخ الانتهاء'**
  String get products_track_expiry;

  /// No description provided for @products_current_stock.
  ///
  /// In ar, this message translates to:
  /// **'المخزون الحالي'**
  String get products_current_stock;

  /// No description provided for @products_disable.
  ///
  /// In ar, this message translates to:
  /// **'تعطيل المنتج'**
  String get products_disable;

  /// No description provided for @products_enable.
  ///
  /// In ar, this message translates to:
  /// **'تفعيل المنتج'**
  String get products_enable;

  /// No description provided for @products_confirm_delete.
  ///
  /// In ar, this message translates to:
  /// **'هل تريد تعطيل هذا المنتج؟'**
  String get products_confirm_delete;

  /// No description provided for @categories_title.
  ///
  /// In ar, this message translates to:
  /// **'الفئات'**
  String get categories_title;

  /// No description provided for @categories_add.
  ///
  /// In ar, this message translates to:
  /// **'إضافة فئة'**
  String get categories_add;

  /// No description provided for @categories_edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل فئة'**
  String get categories_edit;

  /// No description provided for @categories_name.
  ///
  /// In ar, this message translates to:
  /// **'اسم الفئة'**
  String get categories_name;

  /// No description provided for @categories_color.
  ///
  /// In ar, this message translates to:
  /// **'اللون'**
  String get categories_color;

  /// No description provided for @categories_icon.
  ///
  /// In ar, this message translates to:
  /// **'الأيقونة'**
  String get categories_icon;

  /// No description provided for @categories_confirm_delete.
  ///
  /// In ar, this message translates to:
  /// **'هل تريد حذف هذه الفئة؟'**
  String get categories_confirm_delete;

  /// No description provided for @suppliers_title.
  ///
  /// In ar, this message translates to:
  /// **'الموردون'**
  String get suppliers_title;

  /// No description provided for @suppliers_add.
  ///
  /// In ar, this message translates to:
  /// **'إضافة مورد'**
  String get suppliers_add;

  /// No description provided for @suppliers_edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل مورد'**
  String get suppliers_edit;

  /// No description provided for @suppliers_name.
  ///
  /// In ar, this message translates to:
  /// **'اسم المورد'**
  String get suppliers_name;

  /// No description provided for @suppliers_phone.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف'**
  String get suppliers_phone;

  /// No description provided for @suppliers_address.
  ///
  /// In ar, this message translates to:
  /// **'العنوان'**
  String get suppliers_address;

  /// No description provided for @suppliers_notes.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات'**
  String get suppliers_notes;

  /// No description provided for @suppliers_confirm_delete.
  ///
  /// In ar, this message translates to:
  /// **'هل تريد حذف هذا المورد؟'**
  String get suppliers_confirm_delete;

  /// No description provided for @purchases_title.
  ///
  /// In ar, this message translates to:
  /// **'المشتريات'**
  String get purchases_title;

  /// No description provided for @purchases_add.
  ///
  /// In ar, this message translates to:
  /// **'فاتورة شراء جديدة'**
  String get purchases_add;

  /// No description provided for @purchases_invoice_number.
  ///
  /// In ar, this message translates to:
  /// **'رقم الفاتورة'**
  String get purchases_invoice_number;

  /// No description provided for @purchases_date.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الشراء'**
  String get purchases_date;

  /// No description provided for @purchases_select_supplier.
  ///
  /// In ar, this message translates to:
  /// **'اختر المورد'**
  String get purchases_select_supplier;

  /// No description provided for @purchases_add_item.
  ///
  /// In ar, this message translates to:
  /// **'إضافة منتج'**
  String get purchases_add_item;

  /// No description provided for @purchases_save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ الفاتورة'**
  String get purchases_save;

  /// No description provided for @purchases_confirm_save.
  ///
  /// In ar, this message translates to:
  /// **'هل تريد حفظ هذه الفاتورة؟ سيتم تحديث المخزون تلقائياً.'**
  String get purchases_confirm_save;

  /// No description provided for @purchases_cost.
  ///
  /// In ar, this message translates to:
  /// **'سعر الشراء'**
  String get purchases_cost;

  /// No description provided for @purchases_expiry.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الانتهاء'**
  String get purchases_expiry;

  /// No description provided for @purchases_history.
  ///
  /// In ar, this message translates to:
  /// **'سجل المشتريات'**
  String get purchases_history;

  /// No description provided for @purchases_items.
  ///
  /// In ar, this message translates to:
  /// **'بنود الفاتورة'**
  String get purchases_items;

  /// No description provided for @opening_stock_title.
  ///
  /// In ar, this message translates to:
  /// **'الرصيد الافتتاحي'**
  String get opening_stock_title;

  /// No description provided for @opening_stock_description.
  ///
  /// In ar, this message translates to:
  /// **'أدخل الكميات الحالية للمنتجات عند بدء استخدام النظام'**
  String get opening_stock_description;

  /// No description provided for @opening_stock_add_item.
  ///
  /// In ar, this message translates to:
  /// **'إضافة منتج'**
  String get opening_stock_add_item;

  /// No description provided for @opening_stock_save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ الرصيد الافتتاحي'**
  String get opening_stock_save;

  /// No description provided for @opening_stock_current_qty.
  ///
  /// In ar, this message translates to:
  /// **'الكمية الحالية'**
  String get opening_stock_current_qty;

  /// No description provided for @opening_stock_done.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ الرصيد الافتتاحي بنجاح'**
  String get opening_stock_done;

  /// No description provided for @inventory_title.
  ///
  /// In ar, this message translates to:
  /// **'المخزن'**
  String get inventory_title;

  /// No description provided for @inventory_overview.
  ///
  /// In ar, this message translates to:
  /// **'نظرة عامة'**
  String get inventory_overview;

  /// No description provided for @inventory_low_stock.
  ///
  /// In ar, this message translates to:
  /// **'مخزون منخفض'**
  String get inventory_low_stock;

  /// No description provided for @inventory_expiry.
  ///
  /// In ar, this message translates to:
  /// **'تواريخ الانتهاء'**
  String get inventory_expiry;

  /// No description provided for @inventory_adjustments.
  ///
  /// In ar, this message translates to:
  /// **'تسويات المخزن'**
  String get inventory_adjustments;

  /// No description provided for @inventory_adjust.
  ///
  /// In ar, this message translates to:
  /// **'تسوية مخزن'**
  String get inventory_adjust;

  /// No description provided for @inventory_adjustment_type.
  ///
  /// In ar, this message translates to:
  /// **'نوع التسوية'**
  String get inventory_adjustment_type;

  /// No description provided for @inventory_damage.
  ///
  /// In ar, this message translates to:
  /// **'تالف'**
  String get inventory_damage;

  /// No description provided for @inventory_loss.
  ///
  /// In ar, this message translates to:
  /// **'فقدان'**
  String get inventory_loss;

  /// No description provided for @inventory_correction.
  ///
  /// In ar, this message translates to:
  /// **'تصحيح'**
  String get inventory_correction;

  /// No description provided for @inventory_quantity.
  ///
  /// In ar, this message translates to:
  /// **'الكمية'**
  String get inventory_quantity;

  /// No description provided for @inventory_reason.
  ///
  /// In ar, this message translates to:
  /// **'السبب'**
  String get inventory_reason;

  /// No description provided for @inventory_current_stock.
  ///
  /// In ar, this message translates to:
  /// **'المخزون الحالي'**
  String get inventory_current_stock;

  /// No description provided for @inventory_value.
  ///
  /// In ar, this message translates to:
  /// **'القيمة'**
  String get inventory_value;

  /// No description provided for @inventory_expires_in.
  ///
  /// In ar, this message translates to:
  /// **'ينتهي خلال'**
  String get inventory_expires_in;

  /// No description provided for @inventory_days.
  ///
  /// In ar, this message translates to:
  /// **'يوم'**
  String get inventory_days;

  /// No description provided for @inventory_expired.
  ///
  /// In ar, this message translates to:
  /// **'منتهي الصلاحية'**
  String get inventory_expired;

  /// No description provided for @returns_title.
  ///
  /// In ar, this message translates to:
  /// **'المرتجعات'**
  String get returns_title;

  /// No description provided for @returns_customer.
  ///
  /// In ar, this message translates to:
  /// **'مرتجع من عميل'**
  String get returns_customer;

  /// No description provided for @returns_supplier.
  ///
  /// In ar, this message translates to:
  /// **'مرتجع إلى مورد'**
  String get returns_supplier;

  /// No description provided for @returns_invoice_number.
  ///
  /// In ar, this message translates to:
  /// **'رقم الفاتورة الأصلية'**
  String get returns_invoice_number;

  /// No description provided for @returns_return_number.
  ///
  /// In ar, this message translates to:
  /// **'رقم المرتجع'**
  String get returns_return_number;

  /// No description provided for @returns_date.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ المرتجع'**
  String get returns_date;

  /// No description provided for @returns_reason.
  ///
  /// In ar, this message translates to:
  /// **'سبب الإرجاع'**
  String get returns_reason;

  /// No description provided for @returns_select_items.
  ///
  /// In ar, this message translates to:
  /// **'اختر المنتجات المُرجعة'**
  String get returns_select_items;

  /// No description provided for @returns_confirm.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد المرتجع'**
  String get returns_confirm;

  /// No description provided for @returns_history.
  ///
  /// In ar, this message translates to:
  /// **'سجل المرتجعات'**
  String get returns_history;

  /// No description provided for @reports_title.
  ///
  /// In ar, this message translates to:
  /// **'التقارير'**
  String get reports_title;

  /// No description provided for @reports_daily_sales.
  ///
  /// In ar, this message translates to:
  /// **'تقرير المبيعات اليومي'**
  String get reports_daily_sales;

  /// No description provided for @reports_monthly_sales.
  ///
  /// In ar, this message translates to:
  /// **'تقرير المبيعات الشهري'**
  String get reports_monthly_sales;

  /// No description provided for @reports_profit.
  ///
  /// In ar, this message translates to:
  /// **'تقرير الأرباح'**
  String get reports_profit;

  /// No description provided for @reports_top_products.
  ///
  /// In ar, this message translates to:
  /// **'أكثر المنتجات مبيعاً'**
  String get reports_top_products;

  /// No description provided for @reports_inventory_value.
  ///
  /// In ar, this message translates to:
  /// **'قيمة المخزون'**
  String get reports_inventory_value;

  /// No description provided for @reports_purchase_history.
  ///
  /// In ar, this message translates to:
  /// **'سجل المشتريات'**
  String get reports_purchase_history;

  /// No description provided for @reports_date_range.
  ///
  /// In ar, this message translates to:
  /// **'نطاق التاريخ'**
  String get reports_date_range;

  /// No description provided for @reports_generate.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء التقرير'**
  String get reports_generate;

  /// No description provided for @reports_total.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get reports_total;

  /// No description provided for @reports_profit_est.
  ///
  /// In ar, this message translates to:
  /// **'الربح التقديري'**
  String get reports_profit_est;

  /// No description provided for @reports_invoice_count.
  ///
  /// In ar, this message translates to:
  /// **'عدد الفواتير'**
  String get reports_invoice_count;

  /// No description provided for @reports_no_data.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد بيانات في هذه الفترة'**
  String get reports_no_data;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'ku'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'ku':
      return AppLocalizationsKu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
