public without sharing class GVMyAccountController {

    public class AccountInfo {
        @AuraEnabled public String firstName;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean loggedIn;
    }

    @AuraEnabled(cacheable=true)
    public static AccountInfo getMyAccount() {

        AccountInfo result = new AccountInfo();
        result.loggedIn = false;

        List<User> users = [
            SELECT Id, FirstName, LastName, Name,
                   Email, ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (users.isEmpty() || users[0].ContactId == null) {
            return result;
        }

        User customer = users[0];

        result.loggedIn = true;
        result.firstName = String.isBlank(customer.FirstName)
            ? customer.Name
            : customer.FirstName;
        result.fullName = customer.Name;
        result.email = customer.Email;

        return result;
    }
}