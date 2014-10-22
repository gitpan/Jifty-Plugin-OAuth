package Jifty::Plugin::OAuth::View;
use strict;
use warnings;

use Jifty::View::Declare -base;

=head1 NAME

Jifty::Plugin::OAuth::View - Views for OAuth-ey bits

=cut

=head2 oauth/response

Internal template. Do not use.

It returns OAuth parameters to the consumer in the HTTP response body.

=cut

template 'oauth/response' => sub {
    my $params = get 'oauth_response';
    if (ref($params) eq 'HASH') {
        outs_raw join '&',
                 map { sprintf '%s=%s',
                       map { Jifty->web->escape_uri($_) }
                       $_, $params->{$_}
                 } keys %$params;
    }
};

=head2 oauth

An OAuth description page very much geared towards Consumers, since they'll
most likely be the only ones visiting yourapp.com/oauth

=cut

template 'oauth' => page {
    title    => 'OAuth',
    subtitle => 'Information',
}
content {
    p {
        b {
            hyperlink(
                url    => "http://oauth.net/",
                label  => "OAuth",
                target => "_blank",
            )
        };
        outs " is an open protocol to allow secure authentication to users' private data. It's far more secure than users giving out their passwords."
    }

    h2 { "Users" }

    p {
        "OAuth is nearly transparent to end users. Through OAuth, other applications can have secure -- and time-limited -- read and write access to your data on this site."
    }
    p {
        outs "Applications may ask you to ";
        hyperlink(
            label => "authorize a 'token' on our site",
            url   => Jifty->web->url(path => '/oauth/authorize'),
        );
        outs ". This is normal. We want to make sure you approve of other people looking at your data.";
    }

    h2 { "Consumers" }

    p {
        "This application supports OAuth. If you'd like to access the private resources of users of this site, you must first establish a Consumer Key, Consumer Secret, and, if applicable, RSA public key with us. You can do so by contacting " . (Jifty->config->framework('AdminEmail')||'us') . ".";
    }

    p {
        "Once you have a Consumer Key and Consumer Secret, you may begin letting users grant you access to our site. The relevant URLs are:"
    }

    dl {
        dt { "Request a Request Token" }
        dd { Jifty->web->url(path => '/oauth/request_token') }

        dt { "Obtain user authorization for a Request Token" }
        dd { Jifty->web->url(path => '/oauth/authorize') }

        dt { "Exchange a Request Token for an Access Token" }
        dd { Jifty->web->url(path => '/oauth/access_token') }
    }

    p {
        my $restful = 0;
        for (@{ Jifty->config->framework('Plugins') }) {
            if (defined $_->{REST}) {
                $restful = 1;
                last;
            }
        }

        outs "While you have a valid access token, you may browse the site as the user normally does.";

        if ($restful) {
            outs " You may also use ";
            hyperlink(
                url    => Jifty->web->url(path => '=/help'),
                label  => "our REST interface",
                target => "_blank",
            );
            outs ".";
        }
    }
};

=head2 oauth/authorize

This is the page that Users see when authorizing a request token. It renders
the "insert token here" textbox if the consumer didn't put the request token
in the GET query, and (always) renders Allow/Deny buttons.

=cut

template 'oauth/authorize' => page {
    title => 'OAuth',
    subtitle => 'Someone wants stuff!',
}
content {
    show '/oauth/help';

    my $authorize = Jifty->web->new_action(
        moniker => 'authorize_request_token',
        class   => 'AuthorizeRequestToken',
    );

    Jifty->web->form->start();

    # if the site put the token in the request, then use it
    # otherwise, prompt the user for it
    my %args;
    my $token = get 'token';
    if ($token) {
        $args{token} = $token;
    }
    else {
        $authorize->form_field('token')->render;
    }

    $authorize->form_field('use_limit')->render;
    $authorize->form_field('can_write')->render;

    outs_raw $authorize->hidden(callback => get 'callback');

    outs_raw($authorize->button(
        label => 'Deny',
        arguments => { %args, authorize => 'deny' },
    ));

    outs_raw($authorize->button(
        label => 'Allow',
        arguments => { %args, authorize => 'allow' },
    ));

    Jifty->web->form->end();
};

=head2 oauth/authorized

Displayed after the user authorizes or denies a request token. Uses a link
to the callback if provided, otherwise the site's URL.

=cut

template 'oauth/authorized' => page {
    title    => 'OAuth',
    subtitle => 'Authorized',
}
content {
    my $result    = get 'result';
    my $callback  = $result->content('callback');
    my $token     = $result->content('token');
    my $token_obj = $result->content('token_obj');

    $callback ||= $token_obj->consumer->url;

    if (!$callback) {
        p { "Oops! " . $token_obj->consumer->name . " didn't tell us how to get you back to their service. If you do find your way back, you'll probably need this token: " . $token };
    }
    else {
        $callback .= ($callback =~ /\?/ ? '&' : '?')
                  .  'oauth_token='
                  .  $token;
        set consumer => $token_obj->consumer;

        p {
            outs 'To return to ';
            show '/oauth/consumer';
            outs ', ';
            hyperlink(
                label => 'click here',
                url   => $callback,
            );
            outs '.';
        };
    }
};

=head2 oauth/help

This provides a very, very layman description of OAuth for users

=cut

private template 'oauth/help' => sub {
    div {
        p {
            show '/oauth/consumer';
            outs ' is trying to access your data on this site. If you trust this application, you may grant it access.';
        }
        p {
            "If you're at all uncomfortable with the idea of someone rifling through your things, or don't know what this is, click Deny."
        }
        p {
            hyperlink(
                label  => "Learn more about OAuth.",
                url    => "http://oauth.net/",
                target => "_blank",
            )
        }
    }
};

=head2 oauth/consumer

Renders the consumer's name, and if available, its URL as a link.

=cut

private template 'oauth/consumer' => sub {
    my $consumer = (get 'consumer') || 'Some application';

    span {
        outs ref($consumer) ? $consumer->name : $consumer;
        if (ref($consumer) && $consumer->url) {
            outs ' <';
            hyperlink(
                url    => $consumer->url,
                label  => $consumer->url,
                target => "_blank",
            );
            outs ' >';
        }
    }
};

1;

