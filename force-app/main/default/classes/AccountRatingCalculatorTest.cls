/**
 * @description Comprehensive test suite for AccountRatingCalculator.
 *              Validates all functional paths, edge cases, bulk behaviour,
 *              and the Flow invocable entry point.
 *
 *              Coverage target : 90%+ (Protocol v8 requirement)
 *              Security model  : System.runAs() used throughout
 *
 * @author      Agentia Orchestrate Agent
 * @story       AA-118
 */
@IsTest
private class AccountRatingCalculatorTest {

    @TestSetup
    static void makeData() {
        Account hotAcc = new Account(
            Name              = 'Hot Account',
            AnnualRevenue     = 15000000,
            NumberOfEmployees = 1500
        );
        Account warmAcc = new Account(
            Name              = 'Warm Account',
            AnnualRevenue     = 2000000,
            NumberOfEmployees = 200
        );
        Account coldAcc = new Account(
            Name              = 'Cold Account',
            AnnualRevenue     = 50000,
            NumberOfEmployees = 5
        );
        Account zeroAcc = new Account(
            Name              = 'Zero Account',
            AnnualRevenue     = 0,
            NumberOfEmployees = 0
        );
        Account nullAcc = new Account(Name = 'Null Account');

        insert new List<Account>{ hotAcc, warmAcc, coldAcc, zeroAcc, nullAcc };

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 10; i++) {
            opps.add(new Opportunity(
                Name      = 'Hot Opp ' + i,
                AccountId = hotAcc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        for (Integer i = 0; i < 5; i++) {
            opps.add(new Opportunity(
                Name      = 'Warm Opp ' + i,
                AccountId = warmAcc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;
    }

    private static User buildStandardUser() {
        return new User(
            Alias             = 'arcusr',
            Email             = 'arctest@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'TestUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey    = 'America/Los_Angeles',
            UserName          = 'arctest' + System.currentTimeMillis() + '@example.com'
        );
    }

    @IsTest
    static void testSingleRating_Hot() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Hot Account' LIMIT 1];
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Hot', rating, 'Expected Hot for high-value account');
    }

    @IsTest
    static void testSingleRating_Warm() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Warm Account' LIMIT 1];
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Warm', rating, 'Expected Warm for mid-value account');
    }

    @IsTest
    static void testSingleRating_Cold() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cold Account' LIMIT 1];
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Cold', rating, 'Expected Cold for low-value account');
    }

    @IsTest
    static void testSingleRating_ZeroValues() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Zero Account' LIMIT 1];
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Cold', rating, 'Expected Cold for zero-value account');
    }

    @IsTest
    static void testSingleRating_NullFields() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Null Account' LIMIT 1];
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Cold', rating, 'Expected Cold for null-field account');
    }

    @IsTest
    static void testSingleRating_NullId() {
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(null);
            Test.stopTest();
        }
        System.assertEquals(null, rating, 'Null Id should return null');
    }

    @IsTest
    static void testBulkRatings_ThreeAccounts() {
        List<Account> accounts = [
            SELECT Id FROM Account
            WHERE Name IN ('Hot Account', 'Warm Account', 'Cold Account')
        ];
        Set<Id> ids = new Map<Id, Account>(accounts).keySet();
        User u = buildStandardUser();
        insert u;
        Map<Id, String> ratings;
        System.runAs(u) {
            Test.startTest();
            ratings = AccountRatingCalculator.calculateAccountRatings(ids);
            Test.stopTest();
        }
        System.assertEquals(3, ratings.size(), 'Should return ratings for all 3 accounts');
    }

    @IsTest
    static void testBulkRatings_EmptySet() {
        User u = buildStandardUser();
        insert u;
        Map<Id, String> ratings;
        System.runAs(u) {
            Test.startTest();
            ratings = AccountRatingCalculator.calculateAccountRatings(new Set<Id>());
            Test.stopTest();
        }
        System.assert(ratings.isEmpty(), 'Empty input should return empty map');
    }

    @IsTest
    static void testBulkRatings_NullSet() {
        User u = buildStandardUser();
        insert u;
        Map<Id, String> ratings;
        System.runAs(u) {
            Test.startTest();
            ratings = AccountRatingCalculator.calculateAccountRatings(null);
            Test.stopTest();
        }
        System.assert(ratings.isEmpty(), 'Null input should return empty map');
    }

    @IsTest
    static void testUpdateRatings_PersistsHot() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Hot Account' LIMIT 1];
        User u = buildStandardUser();
        insert u;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatings(new Set<Id>{ acc.Id });
            Test.stopTest();
        }
        Account updated = [SELECT Rating FROM Account WHERE Id = :acc.Id LIMIT 1];
        System.assertEquals('Hot', updated.Rating, 'Rating field should be persisted as Hot');
    }

    @IsTest
    static void testUpdateRatings_EmptySet() {
        User u = buildStandardUser();
        insert u;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatings(new Set<Id>());
            Test.stopTest();
        }
        System.assert(true, 'Empty set should complete without exception');
    }

    @IsTest
    static void testUpdateRatings_NullSet() {
        User u = buildStandardUser();
        insert u;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatings(null);
            Test.stopTest();
        }
        System.assert(true, 'Null input should complete without exception');
    }

    @IsTest
    static void testFlowEntry_HappyPath() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Warm Account' LIMIT 1];
        User u = buildStandardUser();
        insert u;
        AccountRatingCalculator.FlowRequest req = new AccountRatingCalculator.FlowRequest();
        req.accountId = acc.Id;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatingFromFlow(
                new List<AccountRatingCalculator.FlowRequest>{ req }
            );
            Test.stopTest();
        }
        Account updated = [SELECT Rating FROM Account WHERE Id = :acc.Id LIMIT 1];
        System.assertEquals('Warm', updated.Rating, 'Flow should persist Warm rating');
    }

    @IsTest
    static void testFlowEntry_NullAccountId() {
        User u = buildStandardUser();
        insert u;
        AccountRatingCalculator.FlowRequest req = new AccountRatingCalculator.FlowRequest();
        req.accountId = null;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatingFromFlow(
                new List<AccountRatingCalculator.FlowRequest>{ req }
            );
            Test.stopTest();
        }
        System.assert(true, 'Null accountId should not throw');
    }

    @IsTest
    static void testFlowEntry_EmptyList() {
        User u = buildStandardUser();
        insert u;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatingFromFlow(
                new List<AccountRatingCalculator.FlowRequest>()
            );
            Test.stopTest();
        }
        System.assert(true, 'Empty FlowRequest list should not throw');
    }

    @IsTest
    static void testFlowEntry_NullList() {
        User u = buildStandardUser();
        insert u;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatingFromFlow(null);
            Test.stopTest();
        }
        System.assert(true, 'Null FlowRequest list should not throw');
    }

    @IsTest
    static void testBulkSafety_200Records() {
        List<Account> bulkAccounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            bulkAccounts.add(new Account(
                Name              = 'Bulk Account ' + i,
                AnnualRevenue     = 500000,
                NumberOfEmployees = 50
            ));
        }
        insert bulkAccounts;
        Set<Id> ids = new Map<Id, Account>(bulkAccounts).keySet();
        User u = buildStandardUser();
        insert u;
        System.runAs(u) {
            Test.startTest();
            AccountRatingCalculator.updateAccountRatings(ids);
            Test.stopTest();
        }
        List<Account> updated = [SELECT Rating FROM Account WHERE Id IN :ids];
        for (Account acc : updated) {
            System.assertEquals('Cold', acc.Rating, 'Rev 500K(1)+Emp 50(1)+0 opps(0)=2 -> Cold');
        }
    }

    @IsTest
    static void testBoundary_ExactRevenueThreshold() {
        Account acc = new Account(
            Name              = 'Boundary Revenue',
            AnnualRevenue     = 10000000,
            NumberOfEmployees = 0
        );
        insert acc;
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Cold', rating, 'Rev 3pts + Emp 0pts + Opp 0pts = 3 -> Cold');
    }

    @IsTest
    static void testBoundary_ExactEmployeeThreshold() {
        Account acc = new Account(
            Name              = 'Boundary Emp',
            AnnualRevenue     = 0,
            NumberOfEmployees = 1000
        );
        insert acc;
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Cold', rating, 'Emp 3pts + Rev 0pts + Opp 0pts = 3 -> Cold');
    }

    @IsTest
    static void testBoundary_WarmToHotTransition() {
        Account acc = new Account(
            Name              = 'Boundary Hot',
            AnnualRevenue     = 10000000,
            NumberOfEmployees = 1000
        );
        insert acc;
        insert new Opportunity(
            Name      = 'One Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Hot', rating, 'Score 7 should yield Hot');
    }

    @IsTest
    static void testBoundary_WarmExactScore() {
        Account acc = new Account(
            Name              = 'Warm Boundary',
            AnnualRevenue     = 1000000,
            NumberOfEmployees = 100
        );
        insert acc;
        User u = buildStandardUser();
        insert u;
        String rating;
        System.runAs(u) {
            Test.startTest();
            rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
            Test.stopTest();
        }
        System.assertEquals('Warm', rating, 'Score 4 should yield Warm');
    }
}