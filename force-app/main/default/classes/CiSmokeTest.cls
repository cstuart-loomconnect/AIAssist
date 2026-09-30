@IsTest
private class CiSmokeTest {
  @IsTest
  static void greetsByName() {
    Test.startTest();
    String result = CiSmoke.greet('World');
    Test.stopTest();
    Assert.areEqual('Hello World', result);
  }
}
