// FILE: lib/web_live_sync/web_app_date_logic.dart
import '../app_date_logic.dart';

class WebAppDateLogic {
  static String getCurrentFYString() => AppDateLogic.getCurrentFYString();
  static String getFYForDate(DateTime dt) => AppDateLogic.getFYForDate(dt);
  static List<String> sortFYList(Iterable<String> fys) => AppDateLogic.sortFYList(fys);
  static DateTime getFYStart(String fy) => AppDateLogic.getFYStart(fy);
  static DateTime getFYEnd(String fy) => AppDateLogic.getFYEnd(fy);
  static String getNextFYString(String currentFY) => AppDateLogic.getNextFYString(currentFY);
  static DateTime getSmartDate(String currentFY) => AppDateLogic.getSmartDate(currentFY);
  static String format(DateTime date) => AppDateLogic.format(date);
  static bool isValidInFY(DateTime pickedDate, String currentFY) => AppDateLogic.isValidInFY(pickedDate, currentFY);
}
