/**
 * @description Stateless service class that calculates and updates Account Rating
 *              (Hot/Warm/Cold) using a point-based scoring model across three
 *              dimensions: Annual Revenue, Number of Employees, and Number of
 *              Opportunities. Separates scoring logic, data access, and update
 *              orchestration for maintainability and testability.
 */
public with sharing class AccountRatingCalculator {

    // Total score boundaries (score range is always 0-9)
    private static final Integer HOT_THRESHOLD = 7;
    private static final Integer WARM_THRESHOLD = 4;

    private static final String RATING_HOT = 'Hot';
    private static final String RATING_WARM = 'Warm';
    private static final String RATING_COLD = 'Cold';

    // Tier configuration. Tiers must remain ordered from highest to lowest threshold.
    private static final List<ScoringTier> REVENUE_TIERS = new List<ScoringTier>{
        new ScoringTier(10000000, 3), // $10M+ -> 3 points
        new ScoringTier(5000000, 2),  // $5M+  -> 2 points
        new ScoringTier(1000000, 1)   // $1M+  -> 1 point
    };

    private static final List<ScoringTier> EMPLOYEE_TIERS = new List<ScoringTier>{
        new ScoringTier(1000, 3), // 1000+ employees -> 3 points
        new ScoringTier(500, 2),  // 500+ employees  -> 2 points
        new ScoringTier(100, 1)   // 100+ employees  -> 1 point
    };

    private static final List<ScoringTier> OPPORTUNITY_TIERS = new List<ScoringTier>{
        new ScoringTier(10, 3), // 10+ opportunities -> 3 points
        new ScoringTier(5, 2),  // 5+ opportunities  -> 2 points
        new ScoringTier(1, 1)   // 1+ opportunity    -> 1 point
    };

    /**
     * @description Calculates the rating for a single Account without persisting it.
     * @param accountId Id of the Account to evaluate
     * @return String Hot, Warm, or Cold. Null if accountId is null or not found.
     */
    public static String calculateAccountRating(Id accountId) {
        if (accountId == null) {
            return null;
        }
        Map<Id, String> ratings = calculateAccountRatings(new Set<Id>{ accountId });
        return ratings.get(accountId);
    }

    /**
     * @description Bulk-safe calculation of ratings for a set of Accounts. Executes a
     *              single SOQL query (with an Opportunity count subquery) regardless of
     *              how many Account Ids are supplied.
     * @param accountIds Set of Account Ids to evaluate
     * @return Map<Id, String> Account Id to calculated rating (Hot/Warm/Cold)
     */
    public static Map<Id, String> calculateAccountRatings(Set<Id> accountIds) {
        Map<Id, String> ratingsById = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) {
            return ratingsById;
        }

        for (Account acc : [
            SELECT Id, AnnualRevenue, NumberOfEmployees,
                   (SELECT Id FROM Opportunities)
            FROM Account
            WHERE Id IN :accountIds
        ]) {
            Integer totalScore = calculateScore(acc);
            ratingsById.put(acc.Id, determineRating(totalScore));
        }

        return ratingsById;
    }

    /**
     * @description Calculates ratings for the given Accounts and persists them to the
     *              Rating field. Runs in system context: this system-computed field is
     *              intentionally exempt from the running user's field-level security,
     *              consistent with the field being presented as Read Only on the page
     *              layout. Uses partial-success DML so one bad record does not block
     *              the batch.
     * @param accountIds Set of Account Ids to recalculate and update
     */
    public static void updateAccountRatings(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        Map<Id, String> ratingsById = calculateAccountRatings(accountIds);
        List<Account> accountsToUpdate = new List<Account>();
        for (Id accId : ratingsById.keySet()) {
            accountsToUpdate.add(new Account(
                Id = accId,
                Rating = ratingsById.get(accId)
            ));
        }

        if (!accountsToUpdate.isEmpty()) {
            List<Database.SaveResult> results = Database.update(accountsToUpdate, false);
            logFailures(results);
        }
    }

    /**
     * @description Invocable entry point exposed to Flow. Recalculates and persists the
     *              Rating for every Account Id supplied by the triggering Flow. Any
     *              downstream failure is caught and logged rather than propagated, so a
     *              secondary automation issue can never roll back the primary record
     *              save that triggered it.
     * @param requests List of FlowRequest wrappers containing Account Ids to process
     */
    @InvocableMethod(
        label='Calculate Account Rating'
        description='Calculates and updates the Rating field for the supplied Accounts based on Annual Revenue, Number of Employees, and Number of Opportunities.'
        category='Account'
    )
    public static void updateAccountRatingFromFlow(List<FlowRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (FlowRequest request : requests) {
            if (request != null && request.accountId != null) {
                accountIds.add(request.accountId);
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }

        try {
            updateAccountRatings(accountIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'AccountRatingCalculator.updateAccountRatingFromFlow failed: ' + ex.getMessage());
        }
    }

    /**
     * @description Aggregates the total score for an Account across all three scoring
     *              dimensions.
     * @param acc Account record populated with AnnualRevenue, NumberOfEmployees, and
     *            the Opportunities child relationship
     * @return Integer Total score in the range 0-9
     */
    private static Integer calculateScore(Account acc) {
        Integer score = 0;
        score += calculateTierScore(acc.AnnualRevenue, REVENUE_TIERS);
        score += calculateTierScore(acc.NumberOfEmployees, EMPLOYEE_TIERS);

        Integer oppCount = (acc.Opportunities != null) ? acc.Opportunities.size() : 0;
        score += calculateTierScore(oppCount, OPPORTUNITY_TIERS);

        return score;
    }

    /**
     * @description Generic tier lookup. Tiers must be supplied in descending threshold
     *              order; the first tier whose threshold the value meets or exceeds
     *              determines the points awarded. Null or non-positive values score 0.
     * @param value Numeric value being scored (revenue, employee count, opportunity count)
     * @param tiers Ordered list of scoring tiers to evaluate
     * @return Integer Points awarded for this dimension (0-3)
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
     * @description Maps a total score to its corresponding rating label.
     * @param totalScore Aggregated score across all dimensions
     * @return String Hot, Warm, or Cold
     */
    private static String determineRating(Integer totalScore) {
        if (totalScore >= HOT_THRESHOLD) {
            return RATING_HOT;
        }
        if (totalScore >= WARM_THRESHOLD) {
            return RATING_WARM;
        }
        return RATING_COLD;
    }

    /**
     * @description Surfaces any DML failures from the partial-success update as a
     *              catchable exception rather than allowing them to fail silently.
     * @param results Save results returned from Database.update(records, false)
     */
    private static void logFailures(List<Database.SaveResult> results) {
        List<String> errors = new List<String>();
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                for (Database.Error err : result.getErrors()) {
                    errors.add(result.getId() + ': ' + err.getMessage());
                }
            }
        }
        if (!errors.isEmpty()) {
            throw new AccountRatingException(
                'Failed to update Rating for one or more Accounts: ' + String.join(errors, '; ')
            );
        }
    }

    /**
     * @description Encapsulates a single scoring threshold/points pair.
     */
    private class ScoringTier {
        private Decimal threshold;
        private Integer points;

        private ScoringTier(Decimal threshold, Integer points) {
            this.threshold = threshold;
            this.points = points;
        }
    }

    /**
     * @description Wrapper class for Flow invocable input parameters.
     */
    public class FlowRequest {
        @InvocableVariable(
            label='Account ID'
            description='Id of the Account to recalculate the Rating for.'
            required=true
        )
        public Id accountId;
    }

    /**
     * @description Custom exception used to surface rating-calculation and DML
     *              errors to calling code that invokes this class directly.
     */
    public class AccountRatingException extends Exception {}
}