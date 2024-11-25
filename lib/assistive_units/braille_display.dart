import 'package:baseerah/assistive_units/assistive_unit.dart';

class BrailleDisplay extends AssistiveUnit {
  BrailleDisplay(String bleAddress)
    : super(
        name: "خلية برايل", 
        description: 'جهاز بريل هو جهاز يستخدم لعرض النصوص بطريقة بريل للأشخاص ذوي الإعاقة البصرية. يقوم هذا الجهاز بترجمة النصوص المكتوبة إلى نمط من النقاط البارزة على سطحه، مما يساعد المستخدمين في قراءة المعلومات والكتب بشكل مستقل.',
        bleAddress: bleAddress
    );

}
