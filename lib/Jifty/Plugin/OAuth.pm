package Jifty::Plugin::OAuth;
use strict;
use warnings;
use base qw/Jifty::Plugin/;

our $VERSION = '0.04';

sub init {
    Jifty::CurrentUser->mk_accessors(qw(is_oauthed oauth_token));

    Jifty::Record->add_trigger(before_access => sub {
        my $record = shift;
        my $right  = shift;

        # not oauthed, so use default
        $record->current_user->is_oauthed
            or return 'ignore';
        my $token = $record->current_user->oauth_token;

        # OAuthed users have no read restrictions, so use default
        return 'ignore' if $right eq 'read';

        # token gives write access, so use default
        return 'ignore' if $token->__value('can_write');

        # we have been forbidden from writing!
        Jifty->log->error("Unable to $right " . ref($record) . " " . ($record->id||'new') . " because the OAuth access token does not allow it.");
        return 'deny';
    });

    for my $type (qw/create set delete/) {
        Jifty::DBI::Record->add_trigger(
            abortable => 1,
            name      => "before_$type",
            callback  => sub {
                my $record = shift;

                # not a Jifty::Object, so allow write
                $record->can('current_user')
                    or return 1;

                # not oauthed, so allow write
                $record->current_user->is_oauthed
                    or return 1;

                my $token = $record->current_user->oauth_token;

                # token gives write access, so allow write
                return 1 if $token->__value('can_write');

                # we have been forbidden from writing!
                Jifty->log->debug("Unable to $type " . ref($record) . " " . ($record->id||'new') . " because the OAuth access token does not allow it.");
                my $ret = Class::ReturnValue->new;
                $ret->as_array(0, "Your OAuth access token denies you write access.");
                $ret->as_error(
                    errno => 1,
                    message => 'Your OAuth access token denies you write access.',
                );
                return $ret->return_value;
            },
        );
    }
}

1;

__END__

=head1 NAME

Jifty::Plugin::OAuth - secure API authorization

=head1 DESCRIPTION

An OAuth web services API for your Jifty app. Users may grant B<limited>
authorization to other applications in a secure way.

This plugin adds an C</oauth> set of URLs to your application, listed below. It
also adds C<is_oauthed> and C<oauth_token> to L<Jifty::CurrentUser>, so you may
have additional restrictions on OAuth access (such as forbidding OAuthed users
to change users' passwords).

=head2 /oauth

This lists some basic information about OAuth, and where to learn more. It also
tells consumers how they may gain OAuth-ability for your site.

=head2 /oauth/request_token

The URL at which consumers POST to get a request token

=head2 /oauth/authorize

The URL at which users authorize request tokens

=head2 /oauth/authorized

After authorizing or denying a request token, users are directed here before
going back to the consumer's site

=head2 /oauth/access_token

The URL that consumers POST to trade an authorized request token for an access
token, with which they may act on the user's behalf

=head1 WARNING

This plugin is beta. Please let us know if there are any issues with it.

=head1 USAGE

Add the following to your config:

 framework:
   Plugins:
     - OAuth: {}

=head1 GLOSSARY

=over 4

=item service provider

A service provider is an application that has users who have private data. This
plugin enables your Jifty application to be an OAuth service provider.

=item consumer

A consumer is an application that wants to access or change users' private
data. The service provider (in this case, this plugin) ensures that this
happens securely and with users' full approval. Without OAuth (or similar
systems), this would be accomplished perhaps by the user giving the consumer
her login information.  Obviously not ideal.

This plugin does not implement the protocol as a consumer, only as a service
provider. You'll likely want more control and flexibility as a consumer.

=item request token

A request token is a unique, random string that a user may authorize for a
consumer.

=item access token

An access token is a unique, random string that a consumer can use to access
private resources on the authorizing user's behalf. Consumers may only
receive an access token if they have an authorized request token.

=back

=head1 NOTES

You must provide consumers access to C</oauth/request_token> and
C</oauth/access_token>.

You could restrict C</oauth/request_token> and C</oauth/access_token> to only
logged-in users and require consumers to log in. Perhaps you could have a
column in your users table that represents whether this user is a consumer and
restrict access to these URLs that way. Or, you could let anyone access these
URLs. This policy is left you as the developer.

Limiting access is wise because each hit to C</oauth/request_token> and
C</oauth/access_token> uses some entropy (so an attacker could run a
denial-of-service attack against you)

You should not allow public access to C</oauth/authorize>. C</oauth/authorize>
will throw a 401 (unauthorized) error if an unauthenticated user accesses it.
On unauthenticated access of C</oauth/authorize>, you should tangent the user
to your login page to improve usability.

You should allow public access to C</oauth>. This has some information for
consumers.

There is currently no way for consumers to add themselves. This might change in
the future, with an OAuth extension. Consumers must contact you and provide you
with the following data:

=over 4

=item consumer_key

An arbitrary string that uniquely identifies a consumer. Preferably something
random over, say, "Hiveminder".

=item secret

A (preferably random) string that is used to ensure that it's really the
consumer you're talking to. After the consumer provides this to you, it's never
sent in plaintext. It is always, however, included in cryptographic signatures.

=item name

A readable name to use in displaying the consumer to users. This is where you'd
put "Hiveminder".

=item url (optional)

The website of the consumer.

=item rsa_key (optional)

The consumer's public RSA key. This is optional. Without it, they will not be
able to use the RSA-SHA1 signature method. They can still use HMAC-SHA1 though.

=back

=head1 TECHNICAL DETAILS

OAuth is an open protocol that enables consumers to access users' private data
in a secure and authorized manner. The way it works is:

=over 4

=item

The consumer establishes a key and a secret with the service provider. This
step only happens once, and is currently manual.

=item

The user is using the consumer's application and decides that she wants to
use some data that she already has on the service provider's application.

=item

The consumer asks the service provider for a request token. The service
provider generates one and gives it to the consumer.

=item

The consumer directs the user to the service provider with that request token.

=item

The user logs in and authorizes that request token.

=item

The service provider directs the user back to the consumer.

=item

The consumer asks the service provider to exchange his authorized request token
for an access token. This access token lets the consumer access resources on
the user's behalf in a limited way, for a limited amount of time.

=back

By establishing secrets and using signatures and timestamps, this can be done
in a very secure manner. For example, a replay attack (an eavesdropper repeats
a request made by a legitimate consumer) is actively defended against.

=head1 METHODS

=head2 init

This adds an is_oauthed accessor to L<Jifty::CurrentUser>. It also establishes
a trigger in L<Jifty::Record> so that only OAuthed consumers with write access
can do anything other than read.

=head1 SEE ALSO

L<Net::OAuth::Request>, L<http://oauth.net/>

=head1 AUTHOR

Shawn M Moore C<< <sartak@bestpractical.com> >>

=head1 LICENSE

Jifty::Plugin::OAuth is Copyright 2007-2008 Best Practical Solutions, LLC.
Jifty::Plugin::OAuth is distributed under the same terms as Perl itself.

=cut

