/**
 * @description Stateless service class that calculates and persists Account ratings
 *              based on a tier-based scoring model across three dimensions:
 *              Annual Revenue, Number of Employees, and Number of Opportunities.
 *
 *              Rating Scale:
 *                Hot  = 7-9 points
 *                Warm = 4-6 points
 *                Cold = 0-3 points
 *
 *              Entry points:
 *                - updateAccountRatingFromFlow  (Invocable - called from Record-Triggered Flow)
 *                - updateAccountRatings         (Bulk DML orchestrator)
 *                - calculateAccountRatings      (Pure scoring, no DML)
 *                - calculateAccountRating       (Single-record convenience wrapper)
 *
 * @author      Agentia Orchestrate Agent
 * @story       AA-118
 */
public with sharing class AccountRatingCalculator {

    // -------------------------------------------------------------------------
    // Inner classes
    // -------------------------------------------------------------------------

    /** Represents a single scoring tier: value >= threshold earns 'points'. */
    @TestVisible
    private class ScoringTier {
        private final Decimal threshold;
        private final Integer points;

        private ScoringTier(Decimal thresholdVal, Integer pointsVal) {
            this.threshold = thresholdVal;
            this.points    = pointsVal;
        }
    }

    /** Invocable request wrapper consumed by the Record-Triggered Flow. */
    public class FlowRequest {
        @InvocableVariable(label='Account Id' required=true)
        public Id accountId;
    }

    // -------------------------------------------------------------------------
    // Tier configuration (descending order - highest threshold first)
    // -------------------------------------------------------------------------

    @TestVisible
    private static final List<ScoringTier> REVENUE_TIERS = new List<ScoringTier>{
        new ScoringTier(10000000, 3),
        new ScoringTier(1000000,  2),
        new ScoringTier(100000,   1)
    };

    @TestVisible
    private static final List<ScoringTier> EMPLOYEE_TIERS = new List<ScoringTier>{
        new ScoringTier(1000, 3),
        new ScoringTier(100,  2),
        new ScoringTier(10,   1)
    };

    @TestVisible
    private static final List<ScoringTier> OPPORTUNITY_TIERS = new List<ScoringTier>{
        new ScoringTier(10, 3),
        new ScoringTier(5,  2),
        new ScoringTier(1,  1)
    };

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * @description Invocable entry point for the Record-Triggered Flow.
     * @param requests List of FlowRequest containing Account Ids to process.
     */
    @InvocableMethod(
        label='Update Account Rating'
        description='Recalculates and saves the Account Rating field based on scoring tiers.'
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
     * @description Calculates ratings for all supplied Account Ids and performs a bulk DML update.
     * @param accountIds Set of Account Ids to process.
     */
    public static void updateAccountRatings(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        Map<Id, String> ratingMap = calculateAccountRatings(accountIds);

        List<Account> toUpdate = new List<Account>();
        for (Id accId : ratingMap.keySet()) {
            toUpdate.add(new Account(Id = accId, Rating = ratingMap.get(accId)));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Pure scoring method - no DML.
     * @param accountIds Set of Account Ids to score.
     * @return Map<Id, String> where value is 'Hot', 'Warm', or 'Cold'.
     */
    public static Map<Id, String> calculateAccountRatings(Set<Id> accountIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) {
            return result;
        }

        Map<Id, Integer> oppCountByAccount = getOpportunityCountByAccount(accountIds);

        List<Account> accounts = [
            SELECT Id, AnnualRevenue, NumberOfEmployees
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ];

        for (Account acc : accounts) {
            Integer score = scoreRevenue(acc.AnnualRevenue)
                          + scoreEmployees(acc.NumberOfEmployees)
                          + scoreOpportunities(oppCountByAccount.get(acc.Id));
            result.put(acc.Id, toRating(score));
        }

        return result;
    }

    /**
     * @description Convenience wrapper: calculates the rating for a single Account.
     * @param accountId The Id of the Account to rate.
     * @return Rating string ('Hot', 'Warm', or 'Cold'), or null if Id is null.
     */
    public static String calculateAccountRating(Id accountId) {
        if (accountId == null) {
            return null;
        }
        Map<Id, String> ratingMap = calculateAccountRatings(new Set<Id>{ accountId });
        return ratingMap.get(accountId);
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private static Map<Id, Integer> getOpportunityCountByAccount(Set<Id> accountIds) {
        Map<Id, Integer> countMap = new Map<Id, Integer>();
        for (Id accId : accountIds) {
            countMap.put(accId, 0);
        }

        for (AggregateResult ar : [
            SELECT AccountId, COUNT(Id) cnt
            FROM Opportunity
            WHERE AccountId IN :accountIds
            WITH USER_MODE
            GROUP BY AccountId
        ]) {
            countMap.put((Id) ar.get('AccountId'), (Integer) ar.get('cnt'));
        }

        return countMap;
    }

    private static String toRating(Integer score) {
        if (score >= 7) { return 'Hot'; }
        if (score >= 4) { return 'Warm'; }
        return 'Cold';
    }

    private static Integer scoreRevenue(Decimal revenue) {
        return scoreValue(revenue == null ? 0 : revenue, REVENUE_TIERS);
    }

    private static Integer scoreEmployees(Integer employees) {
        return scoreValue(employees == null ? 0 : employees, EMPLOYEE_TIERS);
    }

    private static Integer scoreOpportunities(Integer oppCount) {
        return scoreValue(oppCount == null ? 0 : oppCount, OPPORTUNITY_TIERS);
    }

    private static Integer scoreValue(Decimal value, List<ScoringTier> tiers) {
        for (ScoringTier tier : tiers) {
            if (value >= tier.threshold) {
                return tier.points;
            }
        }
        return 0;
    }
}