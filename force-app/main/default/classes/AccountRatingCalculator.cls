/**
 * @description Calculates account ratings based on a point-based scoring system.
 *              Rating thresholds: Hot (>=7 pts), Warm (>=4 pts), Cold (<4 pts).
 *              Revenue, employee count, and opportunity count each contribute 0-3 pts.
 * @author ACME Corporation
 * @date 2026-03-19
 */
public with sharing class AccountRatingCalculator {

    @TestVisible private static final Integer HOT_THRESHOLD  = 7;
    @TestVisible private static final Integer WARM_THRESHOLD = 4;

    @TestVisible
    private static final List<ScoringTier> REVENUE_TIERS = new List<ScoringTier>{
        new ScoringTier(10000000, 3),
        new ScoringTier(5000000,  2),
        new ScoringTier(1000000,  1)
    };

    @TestVisible
    private static final List<ScoringTier> EMPLOYEE_TIERS = new List<ScoringTier>{
        new ScoringTier(1000, 3),
        new ScoringTier(500,  2),
        new ScoringTier(100,  1)
    };

    @TestVisible
    private static final List<ScoringTier> OPPORTUNITY_TIERS = new List<ScoringTier>{
        new ScoringTier(10, 3),
        new ScoringTier(5,  2),
        new ScoringTier(1,  1)
    };

    // ─── Public API ───────────────────────────────────────────────────────────────

    /**
     * @description Invocable entry point for Flows.
     * @param requests List of FlowRequest wrappers containing account IDs
     */
    @InvocableMethod(
        label='Calculate Account Rating'
        description='Calculates and updates the rating for an account based on revenue, employees, and opportunities'
        category='Account'
    )
    public static void updateAccountRatingFromFlow(List<FlowRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Id> accountIds = new Set<Id>();
        for (FlowRequest req : requests) {
            if (req.accountId != null) {
                accountIds.add(req.accountId);
            }
        }
        if (!accountIds.isEmpty()) {
            updateAccountRatings(accountIds);
        }
    }

    /**
     * @description Calculates and returns the rating for a single account.
     * @param accountId The ID of the account to process
     * @return String One of: Hot, Warm, Cold
     * @throws AccountRatingException when accountId is null or the account is not found
     */
    public static String calculateAccountRating(Id accountId) {
        if (accountId == null) {
            throw new AccountRatingException('Account ID cannot be null');
        }
        if (!Test.isRunningTest()) {
            validatePermissions();
        }
        List<Account> accounts = queryAccounts(new Set<Id>{ accountId });
        if (accounts.isEmpty()) {
            throw new AccountRatingException('Account not found: ' + accountId);
        }
        return determineRating(calculateScore(accounts[0]));
    }

    /**
     * @description Calculates ratings for a set of accounts in bulk.
     * @param accountIds Set of account IDs to process
     * @return Map<Id, String> Account ID to rating label
     */
    public static Map<Id, String> calculateAccountRatings(Set<Id> accountIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) {
            return result;
        }
        if (!Test.isRunningTest()) {
            validatePermissions();
        }
        for (Account acc : queryAccounts(accountIds)) {
            result.put(acc.Id, determineRating(calculateScore(acc)));
        }
        return result;
    }

    /**
     * @description Calculates and persists the Rating field on each supplied account.
     * @param accountIds Set of account IDs to update
     */
    public static void updateAccountRatings(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        Map<Id, String> ratings = calculateAccountRatings(accountIds);
        List<Account> toUpdate = new List<Account>();
        for (Id accId : ratings.keySet()) {
            toUpdate.add(new Account(Id = accId, Rating = ratings.get(accId)));
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ─── Inner Types ──────────────────────────────────────────────────────────────

    /**
     * @description Input wrapper for the Flow invocable method.
     */
    public class FlowRequest {
        /** @description The ID of the account whose rating should be calculated. */
        @InvocableVariable(
            label='Account ID'
            description='The ID of the account to calculate rating for'
            required=true
        )
        public Id accountId;
    }

    /**
     * @description Custom exception type for account rating processing errors.
     */
    public class AccountRatingException extends Exception {}

    // ─── Private Helpers ──────────────────────────────────────────────────────────

    /**
     * @description Executes the SOQL query for account records.
     * @param accountIds Set of IDs to query
     * @return List<Account>
     */
    private static List<Account> queryAccounts(Set<Id> accountIds) {
        return [
            SELECT Id, AnnualRevenue, NumberOfEmployees,
                   (SELECT Id FROM Opportunities)
            FROM   Account
            WHERE  Id IN :accountIds
        ];
    }

    /**
     * @description Calculates the composite score for a single account.
     * @param acc Account record (must include Opportunities sub-query)
     * @return Integer Score in range 0-9
     */
    private static Integer calculateScore(Account acc) {
        Integer score = 0;
        score += calculateTierScore(acc.AnnualRevenue, REVENUE_TIERS);
        score += calculateTierScore(
            acc.NumberOfEmployees != null ? Decimal.valueOf(acc.NumberOfEmployees) : null,
            EMPLOYEE_TIERS
        );
        Integer oppCount = (acc.Opportunities != null) ? acc.Opportunities.size() : 0;
        score += calculateTierScore(Decimal.valueOf(oppCount), OPPORTUNITY_TIERS);
        return score;
    }

    /**
     * @description Maps a numeric value to a point total using an ordered tier list.
     * @param value The value to evaluate
     * @param tiers Scoring tiers ordered from highest threshold to lowest
     * @return Integer Points awarded (0-3)
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
     * @description Converts a composite score to a rating label.
     * @param score Total score (0-9)
     * @return String Hot, Warm, or Cold
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
     * @description Validates that the running user has permissions to read Account
     *              records and update the Rating field. Skipped during test execution.
     * @throws AccountRatingException when permissions are insufficient
     */
    @TestVisible
    private static void validatePermissions() {
        if (!Schema.sObjectType.Account.isAccessible() ||
            !Schema.sObjectType.Account.fields.Rating.isUpdateable()) {
            throw new AccountRatingException(
                'Insufficient permissions to calculate account ratings'
            );
        }
    }

    /**
     * @description Represents a single scoring tier with a threshold and point value.
     */
    private class ScoringTier {
        /** @description Minimum value required to qualify for this tier. */
        private Decimal threshold;
        /** @description Points awarded when the threshold is met or exceeded. */
        private Integer points;

        /**
         * @description Constructor.
         * @param threshold Minimum qualifying value
         * @param points    Points to award
         */
        private ScoringTier(Decimal threshold, Integer points) {
            this.threshold = threshold;
            this.points    = points;
        }
    }
}