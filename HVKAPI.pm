package HVKAPI;

#    HVKAPI - class for vkontakte.ru API
#    Copyright (C) 2011-2012 Hagall (asbrandr@jabber.ru)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#    Rev4, 111128

use warnings;
use strict;
use utf8;

use LWP::Simple;
use LWP::Protocol::https;
use HTTP::Cookies;
use Data::Dumper;
use JSON;
use Encode qw(encode_utf8);


our $VERSION = '1.0';
our $appId = 2256065;					# ID ���������� ����������
our $appSettings = 'friends,photos,audio,video,docs,notes,pages,wall,groups,messages';
our $defaultAgent = 'Mozilla/5.0 (X11; Linux x86_64; rv:9.0.1) Gecko/20100101 Firefox/9.0.1';
our $defaultApiUrl = 'http://api.vk.com/api.php'; # URL ��� API-��������

our @ISA = qw(Exporter);

#-----------------------------------------------------------------------------------------
#							����������� ������.
#							Rev2, 110605
sub new {
	my $class = shift;
	my $self  = {};
	bless( $self, $class );

	($self->{captcha_callback}, $self->{api_id}, $self->{useragent}) = @_;
	$self->{useragent} || ($self->{useragent} = $defaultAgent);
	$self->{api_id} || ($self->{api_id} = $appId);
	$self->{app_settings} = $appSettings;


	$self->{api_url} = $defaultApiUrl;
	return $self;
}


#-----------------------------------------------------------------------------------------
#							����� callback ��� �����
#							Rev1, 110605
sub setCallback
{
	my ($self, $callback) = @_;
	$self->{captcha_callback} = $callback;
	return $callback;
}


#-----------------------------------------------------------------------------------------
#							�������������� ������
#							Rev2, 120121
sub restoreSession
{
	my $self = shift;
	($self->{access_token}, $self->{mid}) = @_;
	$self->{browser} = new LWP::UserAgent(agent => $self->{useragent});
	return 0;
}


#-----------------------------------------------------------------------------------------
#							��������� ���������� ������
#							Rev2, 120121
sub getSessionVars
{
	my $self = shift;
	return { "access_token" => $self->{access_token}, "mid" => $self->{mid} };
}

#-----------------------------------------------------------------------------------------
#							����� � API ��� ����������
#							Rev6, 120207
sub login
{
	my $self = shift;

	my ($ulogin, $upass, $mphone) = @_;


	my ($app_id, $app_settings) 			= ($self->{api_id}, $self->{app_settings});
	my $captchaCallback 				= $self->{captcha_callback};

	($self->{mid}, $self->{access_token})		= (0, 0);
	$self->{browser} 				= LWP::UserAgent->new();

	my $browser 					= $self->{browser};
	$browser->agent($self->{useragent});
	$browser->cookie_jar(new HTTP::Cookies());
	$browser->default_header("Accept" 		=> "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
	$browser->default_header("Accept-Language" 	=> "ru-ru,ru;q=0.8,en-us;q=0.5,en;q=0.3");
	#$browser->default_header("Accept-Encoding" 	=> "gzip, deflate");
	$browser->default_header("Accept-Charset"	=> "utf-8;q=0.7,*;q=0.7");

	my $response 					= $browser->get("http://oauth.vk.com/oauth/authorize?client_id=$appId".
									"&scope=$appSettings".
									"&display=wap&response_type=token");

	my ($ip_h) 					= $response->decoded_content() =~ /name="ip_h" value="(\w+)"/;
	my ($to_link) 					= $response->decoded_content() =~ /name="to" value="([\w\/]+)"/;


	return ('errcode' => 100,
	        'errdesc' => 'Cannot parse initial parameters!') unless ($ip_h && $to_link);

	my ($captcha_sid, $captcha_key);

	do
	{
											# ������������ �����
											# � �������� �����
		if ($captcha_sid)
		{
			my $cdata 			= {'captcha_url' => "http://vk.com/captcha.php?sid=$captcha_sid&dif=0",
							   'captcha_sid' => $captcha_sid,
							   'difficulty'  => 0
							  };
			my $callback = $self->{captcha_callback};
			$captcha_key = &$callback($cdata);
		}

		$response				= $browser->post("https://login.vk.com/?act=login&soft=1&utf8=1",
										{"q"			=> 1,
										 "from_host" 		=> "oauth.vk.com",
										 "from_protocol" 	=> "http",
										 "ip_h" 		=> $ip_h,
										 "to" 			=> $to_link,
										 "email" 		=> $ulogin,
										 "pass" 		=> $upass,
										 "act"			=> "login",
										 "soft"			=> 1,
										 "utf8"			=> 1,
										 "captcha_sid"		=> $captcha_sid,
										 "captcha_key"		=> $captcha_key
										});

		my $old_location 			= $response->header('Location');

		$response 				= $browser->get($response->header('Location'))
								if ($response->header('Location'));

		($captcha_sid)				= $response->decoded_content() =~ /name="captcha_sid" value="(\d+)"/;

	}
	while ($captcha_sid);

	my ($access_token, $user_id);
	($access_token, $user_id)			= $response->previous()->header('Location') =~ /access_token=(\w+).*?user_id=(\d+)/
							  if ($response->previous());

	unless ($access_token && $user_id)
	{
											# ��������� � ������ ���, �����
											# ��������� ���������
		my ($link) 				= $response->decoded_content() =~ /(oauth\.vk\.com.*?)"/;

		return ('errcode' => 101,
			'errdesc' => 'Cannot parse redirect link!') unless ($link);

		$response				= $browser->post("https://$link");
		$response 				= $browser->get($response->header('Location'))
							if ($response->header('Location'));

		my $redirect 				= $response->previous()->header("Location");
		($access_token, $user_id) 		= $redirect =~ /access_token=(\w+).*?user_id=(\d+)/;

	}

	return ('errcode' => 102,
		'errdesc' => 'Cannot parse acess token and user id!') unless ($access_token && $user_id);

											# �������� ������������
											# � ��������� ���������� cookies
	$response					= $browser->get("http://vk.com");
	($ip_h)						= $response->decoded_content() =~ /ip_h=(\w+)/;
	$response					= $browser->get("https://login.vk.com/?al_frame=1&from_host=vk.com&from_protocol=http&ip_h=$ip_h");
	$response					= $browser->get("http://vk.com/id1");

	if ($response->decoded_content() =~ /security_check/)
	{
		return ('errcode' => 103,
			'errdesc' => 'Holy shit! Security check!') unless ($mphone);

		my ($hash) 				= $response->content =~ /hash: \'(.*)\'}/;
		return ('errcode' => 104,
			'errdesc' => 'Cannot parse security hash!') unless ($hash);

		$response 				= $browser->get("http://vk.com/login.php?act=security_check".
												"&code=$mphone".
												"&to=".
												"&al_page=".
												"&hash=$hash");
		return ('errcode' => 105,
			'errdesc' => 'Cannot pass security check!') unless ((defined $response->previous()) &&
									    !($response->previous()->header("Location") =~ /security_check/));

		$response				= $browser->get("http://vk.com");
#		($ip_h)					= $response->decoded_content() =~ /ip_h=(\w+)/;
#		$response				= $browser->get("https://login.vk.com/?al_frame=1&from_host=vk.com&from_protocol=http&ip_h=$ip_h");

	}

	$self->{browser} 				= $browser;
	$self->{mid} 					= $user_id;
	$self->{access_token}				= $access_token;

	return ('errcode' => 0,
		'mid'	  => $user_id,
		'errdesc' => '');

}


#-----------------------------------------------------------------------------------------
#							��������� ������ �� ������-�������
#							Rev1, 110605
sub interface
{
	my $self = shift;
	return $self->{browser};
}


#-----------------------------------------------------------------------------------------
#							������ � �������� � ����������
#							�����. ������������ ������ �
#							������
#							Rev1, 110331
#
sub postWithCaptcha
{
	my ($self, $browser, $link, $post) = @_;

	bless $browser, "LWP::UserAgent";

	my $response = $browser->post($link, $post);
	my $callback = $self->{captcha_callback};

	while ($response->content =~ /captcha_sid/)
	{
		return undef unless defined $callback;

		utf8::encode($response->content);
		my $cdata = decode_json($response->content);
		my $sid = $cdata->{'captcha_sid'};
		$cdata->{'difficult'} = 0 unless ($cdata->{'difficult'});

		my $diff = abs (int $cdata->{'difficult'} - 1);
		$cdata->{'captcha_url'} = "http://vk.com/captcha.php?sid=$sid&s=$diff";
		$post->{'captcha_sid'} = $cdata->{'captcha_sid'};
		$post->{'captcha_key'} = &$callback($cdata);
		$response = $browser->post($link, $post);
	}

	return $response;
}


#-----------------------------------------------------------------------------------------
#							������ � API
#							Rev1, 120121
sub request {
	my ($self, $method, $params) = @_;

	my $browser = $self->{browser};
	bless $browser, "LWP::UserAgent";

	my $reqstr = join "&", map { $_."=".$params->{$_} } keys %$params;
	$reqstr .= "&access_token=".$self->{access_token};

	my $response = $browser->get("https://api.vk.com/method/$method?$reqstr");

	my $result;
							# � ����� �� ������?
	unless (eval { $result = decode_json($response->content) })
	{
		$result->{error}->{error_code} = 555;
		$result->{error}->{error_desc} = $response->content;
		return $result;
	}

							# Captcha is needed.
	if ($result->{error}->{error_code} and $result->{error}->{error_code} == 14)
	{
		my $callback = $self->{captcha_callback};
		my $answer = &$callback({ "captcha_url" => $result->{error}->{captcha_img},
		                          "captcha_sid" => $result->{error}->{captcha_sid}
		                        });
		$params->{captcha_sid} = $result->{error}->{captcha_sid};
		$params->{captcha_key} = $answer;
	        return $self->request($method, $params);
	}

	return $result;
}


1;

