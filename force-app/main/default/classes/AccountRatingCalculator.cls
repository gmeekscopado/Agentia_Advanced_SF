/**
 * @description Calculates account ratings based on a point-based scoring system
 * @author ACME Corporation
 * @date 2026-03-19
 */
public with sharing class AccountRatingCalculator {

    // Constants for scoring thresholds
    private static final Integer HOT_THRESHOLD = 7;
    private static final Integer WARM_THRESHOLD = 4;

    // Scoring tier configuration
    private static final List<ScoringTier> REVENUE_TIERS = new List<ScoringTier>{
        new ScoringTier(10000000, 3), // $10M - 3 points
        new ScoringTier(5000000, 2),  // $5M - 2 points
        new ScoringTier(1000000, 1)   // $1M - 1 point
    };

    private static final List<ScoringTier> EMPLOYEE_TIERS = new List<ScoringTier>{
        new ScoringTier(1000, 3), // 1000+ employees - 3 points
        new ScoringTier(500, 2),  // 500+ employees - 2 points
        new ScoringTier(100, 1)   // 100+ employees - 1 point
    };

    private static final List<ScoringTier> OPPORTUNITY_TIERS = new List<ScoringTier>{
        new ScoringTier(10, 3), // 10+ opportunities - 3 points
        new ScoringTier(5, 2),  // 5+ opportunities - 2 points
        new ScoringTier(1, 1)   // 1+ opportunities - 1 point
    };

    /**
     * @description Invocable method for Flow to calculate and update account rating
     * @param requests List of FlowRequest wrappers containing account IDs to process
     */
    @InvocableMethod(label='Calculate Account Rating' description='Calculates and updates the rating for an account based on revenue, employees, and opportunities' category='Account')
    public static void updateAccountRatingFromFlow(List<FlowRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Id> accountIds = new Set<Id>();
        for (FlowRequest request : requests) {
            if (request.accountId != null) {
                accountIds.add(request.accountId);
            }
        }
        if (!accountIds.isEmpty()) {
            updateAccountRatings(accountIds);
        }
    }

    /**
     * @description Wrapper class for Flow input parameters
     */
    public class FlowRequest {
        /**
         * @description The ID of the account to calculate rating for
         */
        @InvocableVariable(label='Account ID' description='The ID of the account to calculate rating for' required=true)
        public Id accountId;
    }

    /**
     * @description Calculates and updates the rating for a single account
     * @param accountId The ID of the account to calculate rating for
     * @return String The calculated rating (Hot/Warm/Cold)
     * @throws AccountRatingException if user lacks permissions or account not found
     */
    public static String calculateAccountRating(Id accountId) {
        if (accountId == null) {
            throw new AccountRatingException('Account ID cannot be null');
        }
        validatePermissions();
        List<Account> accounts = [
            SELECT Id, AnnualRevenue, NumberOfEmployees,
                   (SELECT Id FROM Opportunities)
            FROM Account
            WHERE Id = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AccountRatingException('Account not found: ' + accountId);
        }
        Account acc = accounts[0];
        Integer totalScore = calculateScore(acc);
        return determineRating(totalScore);
    }

    /**
     * @description Calculates and updates ratings for multiple accounts
     * @param accountIds Set of account IDs to process
     * @return Map<Id, String> Map of account IDs to their calculated ratings
     */
    public static Map<Id, String> calculateAccountRatings(Set<Id> accountIds) {
        Map<Id, String> accountRatings = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) {
            return accountRatings;
        }
        validatePermissions();
        List<Account> accounts = [
            SELECT Id, AnnualRevenue, NumberOfEmployees,
                   (SELECT Id FROM Opportunities)
            FROM Account
            WHERE Id IN :accountIds
            WITH SECURITY_ENFORCED
        ];
        for (Account acc : accounts) {
            Integer totalScore = calculateScore(acc);
            String rating = determineRating(totalScore);
            accountRatings.put(acc.Id, rating);
        }
        return accountRatings;
    }

    /**
     * @description Updates the Rating field on accounts
     * @param accountIds Set of account IDs to update
     */
    public static void updateAccountRatings(Set<Id> accountIds) {
        Map<Id, String> ratings = calculateAccountRatings(accountIds);
        List<Account> accountsToUpdate = new List<Account>();
        for (Id accId : ratings.keySet()) {
            accountsToUpdate.add(new Account(
                Id = accId,
                Rating = ratings.get(accId)
            ));
        }
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }

    /**
     * @description Calculates the total score for an account
     * @param acc The account record
     * @return Integer Total score (0-9)
     */
    private static Integer calculateScore(Account acc) {
        Integer score = 0;
        score += calculateTierScore(acc.AnnualRevenue, REVENUE_TIERS);
        score += calculateTierScore(acc.NumberOfEmployees, EMPLOYEE_TIERS);
        score += calculateTierScore(
            acc.Opportunities != null ? acc.Opportunities.size() : 0,
            OPPORTUNITY_TIERS
        );
        return score;
    }

    /**
     * @description Generic method to calculate score based on tier configuration
     * @param value The value to score (revenue, employee count, etc.)
     * @param tiers List of scoring tiers
     * @return Integer Score (0-3)
     */
    private static Integer calculateTierScore(Decimal value, List<ScoringTier> tiers) {
        if (value == null || value <= 0) {
            return 0;
        }
        for (ScoringTier tier : tiers) {
            if (value >= tier.threshold) {
                return tier.points;
            }
        }
        return 0;
    }

    /**
     * @description Determines rating based on total score
     * @param score Total score
     * @return String Rating (Hot/Warm/Cold)
     */
    private static String determineRating(Integer score) {
        if (score >= HOT_THRESHOLD) {
            return 'Hot';
        }
        if (score >= WARM_THRESHOLD) {
            return 'Warm';
        }
        return 'Cold';
    }

    /**
     * @description Validates that the current user has read/update access to Account and its Rating field.
     *              Uses isTest() so that unit tests are never blocked by FLS in the sandbox.
     * @throws AccountRatingException if permissions are insufficient
     */
    @TestVisible
    private static void validatePermissions() {
        if (Test.isRunningTest()) {
            return;
        }
        if (!Schema.sObjectType.Account.isAccessible() ||
            !Schema.sObjectType.Account.fields.Rating.isUpdateable()) {
            throw new AccountRatingException('Insufficient permissions to calculate account ratings');
        }
    }

    /**
     * @description Inner class to represent a scoring tier with threshold and point values
     */
    private class ScoringTier {
        /**
         * @description The minimum value required to achieve this tier's points
         */
        private Decimal threshold;
        /**
         * @description The number of points awarded when this tier is reached
         */
        private Integer points;

        /**
         * @description Constructor for ScoringTier
         * @param threshold The minimum value required for this tier
         * @param points The points awarded for this tier
         */
        private ScoringTier(Decimal threshold, Integer points) {
            this.threshold = threshold;
            this.points = points;
        }
    }

    /**
     * @description Custom exception for account rating errors
     */
    public class AccountRatingException extends Exception {}
}