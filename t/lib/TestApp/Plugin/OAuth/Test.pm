#!/usr/bin/env perl
package TestApp::Plugin::OAuth::Test;
use strict;
use warnings;
use base qw/Jifty::Test/;

use MIME::Base64;
use Digest::HMAC_SHA1 'hmac_sha1';
use Jifty::Test::WWW::Mechanize;

our @EXPORT = qw($timestamp $url $umech $cmech $pubkey $seckey $token_obj
                 $server $URL response_is sign get_latest_token allow_ok deny_ok
                 _authorize_request_token get_request_token get_authorized_token
                 get_access_token has_rsa rsa_skip start_server);

our $timestamp = 0;
our $url;
our $umech;
our $cmech;
our $pubkey = slurp('t/t/id_rsa.pub');
our $seckey = slurp('t/t/id_rsa');
our $token_obj;
our $server;
our $URL;
our $can_write;

sub setup {
    my $class = shift;
    $class->SUPER::setup;
    $class->export_to_level(1);
}

sub start_server {
    $server  = Jifty::Test->make_server;
    $URL     = $server->started_ok;
    $umech   = Jifty::Test::WWW::Mechanize->new();
    $cmech   = Jifty::Test::WWW::Mechanize->new();
    $url     = $URL . '/oauth/request_token';
}

sub response_is {
    ++$timestamp;

    my %params = (
        oauth_timestamp        => $timestamp,
        oauth_nonce            => scalar(reverse $timestamp),
        oauth_signature_method => 'HMAC-SHA1',
        oauth_version          => '1.0',

        code                   => 400,
        testname               => "",
        method                 => 'POST',
        token_secret           => '',
        params_in              => 'method',
        @_,
    );

    local $url = $URL . delete $params{url}
        if $params{url};

    for (grep {!defined $params{$_}} keys %params) {
        delete $params{$_};
    }

    my $code            = delete $params{code};
    my $testname        = delete $params{testname} || "Response was $code";
    my $no_token        = delete $params{no_token};
    my $method          = delete $params{method};
    my $params_in       = delete $params{params_in};
    my $token_secret    = delete $params{token_secret};
    my $consumer_secret = delete $params{consumer_secret}
        or die "consumer_secret not passed to response_is!";

    if ($url =~ /access_token/) {
        $token_secret ||= $token_obj->secret;
        $params{oauth_token} ||= $token_obj->token;
    }

    $params{oauth_signature} ||= sign($method, $token_secret, $consumer_secret, %params);

    my $r;

    if ($params_in eq 'authz') {
        $cmech->default_header("Authorization" => authz(%params));
    }

    if ($method eq 'GET') {
        my $query = join '&',
                    map { "$_=" . Jifty->web->escape_uri($params{$_}||'') }
                    keys %params;
        my $params = $params_in eq 'method' ? "?$query" : '';
        $r = $cmech->get("$url$params");
    }
    else {
        my $req = HTTP::Request->new(
            uc($method) => $url,
        );

        if ($params_in eq 'method') {
            # avoid Encode complaining about undef
            for (values %params) {
                defined or $_ = '';
            }

            my $content = Jifty->web->query_string(%params);
            $req->header('Content-type' => 'application/x-www-form-urlencoded');
            $req->content($content);
        }

        $r = $cmech->request($req);
    }

    $cmech->default_headers->remove_header("Authorization");

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    main::is($r->code, $code, $testname);

    if ($url =~ /oauth/) {
        undef $token_obj;
        get_latest_token();

        if ($no_token || $code != 200) {
            main::ok(!$token_obj, "Did not get a token");
        }
        elsif ($code == 200) {
            main::ok($token_obj, "Successfully loaded a token object with token ".$token_obj->token.".");
        }
    }

    return $cmech->content;
}

# creates an Authorization header
sub authz {
    my %params = @_;

    return "OAuth "
         . join ', ',
             map { $_ . q{="} . Jifty->web->escape_uri($params{$_}) . q{"} }
                keys %params;
}

sub sign {
    my ($method, $token_secret, $consumer_secret, %params) = @_;

    local $url = delete $params{sign_url} || $url;

    my $key = delete $params{signature_key};
    my $sig_method = $params{oauth_signature_method} || delete $params{_signature_method};

    delete $params{oauth_signature};

    if ($sig_method eq 'PLAINTEXT') {
        my $signature = join '&',
                        map { Jifty->web->escape_uri($_||'') }
                            $consumer_secret,
                            $token_secret;
        return $signature;
    }

    my $normalized_request_parameters
        = join '&',
          map { "$_=" . Jifty->web->escape_uri($params{$_}||'') }
          sort keys %params;

    my $signature_base_string
        = join '&',
          map { Jifty->web->escape_uri($_||'') }
              uc($method),
              $url,
              $normalized_request_parameters;

    my $signature;

    if ($sig_method eq 'RSA-SHA1') {
        require Crypt::OpenSSL::RSA;
        my $pubkey = Crypt::OpenSSL::RSA->new_private_key($key);
        $signature = encode_base64($pubkey->sign($signature_base_string), "");
    }
    elsif ($sig_method eq 'HMAC-SHA1') {
        my $key = join '&',
          map { Jifty->web->escape_uri($_||'') }
              $consumer_secret,
              $token_secret;
        my $hmac = Digest::HMAC_SHA1->new($key);
        $hmac->add($signature_base_string);
        $signature = encode_base64($hmac->digest, '');
    }

    return ($signature, $signature_base_string, $normalized_request_parameters)
        if wantarray;
    return $signature;

}

sub has_rsa {
    eval { require Crypt::OpenSSL::RSA; 1 }
}

sub rsa_skip {
    my $count = shift || Carp::carp "You must specify a number of tests to skip.";
    ::skip 'Crypt::OpenSSL::RSA is required for these tests', $count unless has_rsa;
}

sub slurp {
    no warnings 'once';
    my $file = shift;
    local $/;
    local @ARGV = $file;
    my $contents = scalar <>
        or die "Unable to slurp $file";
    return $contents;
}

sub get_latest_token {
    my $content = $cmech->content;

    $content =~ s/\boauth_token=(\w+)//
        or return;
    my $token = $1;

    $content =~ s/\boauth_token_secret=(\w+)//
        or return;
    my $secret = $1;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    main::is($content, '&', "the output was exactly oauth_token=...&oauth_secret=...");

    my $package = 'Jifty::Plugin::OAuth::Model::';

    if ($cmech->uri =~ /request_token/) {
        $package .= 'RequestToken';
    }
    elsif ($cmech->uri =~ /access_token/) {
        $package .= 'AccessToken';
    }
    else {
        Jifty->log->error("Called get_latest_token, but I cannot grok the URI " . $cmech->uri);
        return;
    }

    $token_obj = $package->new(current_user => Jifty::CurrentUser->superuser);
    $token_obj->load_by_cols(token => $token);

    if (!$token_obj->id) {
        Jifty->log->error("Could not find a $package with token $token");
        return;
    }

    return $token_obj;
}

sub allow_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $error = _authorize_request_token('Allow');
    ::fail($error), return if $error;

    my $name = $token_obj->consumer->name;
    if ($can_write) {
        $umech->content_contains("Allowing $name to read and write your data for 1 hour.");
    }
    else {
        $umech->content_contains("Allowing $name to read your data for 1 hour.");
    }
}

sub deny_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $error = _authorize_request_token('Deny');
    ::fail($error), return if $error;

    my $name = $token_obj->consumer->name;
    $umech->content_contains("Denying $name the right to access your data.");
}

sub _authorize_request_token {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $which_button = shift
        or die "You did not specify a button to click to _authorize_request_token";

    my $token = shift || $token_obj->token;
    $token = $token->token if ref $token;

    $umech->get('/oauth/authorize')
        or return "Unable to navigate to /oauth/authorize";;
    $umech->content =~ /If you trust this application/
        or return "Content did not much qr/If you trust this application/";
    my $moniker = $umech->moniker_for('TestApp::Plugin::OAuth::Action::AuthorizeRequestToken')
        or return "Unable to find moniker for AuthorizeRequestToken";
    $umech->fill_in_action($moniker,
        token => $token,
        can_write => $can_write,
    ) or return "Unable to fill in the AuthorizeRequestToken action";
    $umech->click_button(value => $which_button)
        or return "Unable to click $which_button button";
    return;
}

sub get_request_token {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    response_is(
        url                    => '/oauth/request_token',
        code                   => 200,
        testname               => "200 - plaintext signature",
        consumer_secret        => 'bar',
        oauth_consumer_key     => 'foo',
        oauth_signature_method => 'PLAINTEXT',
        @_,
    );
    return $token_obj;
}

sub get_authorized_token {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    get_request_token(@_);
    allow_ok();
    return $token_obj;
}

sub get_access_token {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    get_authorized_token() unless shift;
    response_is(
        url                    => '/oauth/access_token',
        code                   => 200,
        testname               => "200 - plaintext signature",
        consumer_secret        => 'bar',
        oauth_consumer_key     => 'foo',
        oauth_signature_method => 'PLAINTEXT',
    );
}

1;

