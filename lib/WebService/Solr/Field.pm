package WebService::Solr::Field;

use strict;
use warnings;

use WebService::Solr ();
use XML::Easy::Element;
use XML::Easy::Content;
use XML::Easy::Text ();

sub new {
    my ( $class, $name, $value, $opts ) = @_;
    $opts ||= {};

    die "name required"  unless defined $name;
    die "value required" unless defined $value;

    my $self = {
        name  => $name,
        value => WebService::Solr::_decode($value),
        %{ $opts },
    };

    return bless $self, $class;
}

sub name {
    my $self = shift;
    $self->{ name } = $_[ 0 ] if @_;
    return $self->{ name };
}

sub value {
    my $self = shift;
    $self->{ value } = WebService::Solr::_decode($_[ 0 ]) if @_;
    return $self->{ value };
}

sub boost {
    my $self = shift;
    $self->{ boost } = $_[ 0 ] if @_;
    return $self->{ boost };
}

sub to_element {
    my $self = shift;
    my %attr = ( $self->boost ? ( boost => $self->boost ) : () );

    return XML::Easy::Element->new(
        'field',
        { name => $self->name, %attr },
        XML::Easy::Content->new( [ $self->value ] ),
    );
}

sub to_xml {
    my $self = shift;

    return XML::Easy::Text::xml10_write_element( $self->to_element );
}

1;

__END__

=head1 NAME

WebService::Solr::Field - A field object

=head1 SYNOPSIS

    my $field = WebService::Solr::Field->new( foo => 'bar' );

=head1 DESCRIPTION

This class represents a field from a document, which is basically a
name-value pair.

=head1 ACCESSORS

=over 4

=item * name - the field's name

=item * value - the field's value

=item * boost - a floating-point boost value

=back

=head1 METHODS

=head2 new( $name => $value, \%options )

Creates a new field object. Currently, the only option available is a
"boost" value.

=head2 BUILDARGS( @args )

A Moo override to allow our custom constructor.

=head2 to_element( )

Serializes the object to an XML::Easy::Element object.

=head2 to_xml( )

Serializes the object to xml.

=head1 AUTHORS

Andy Lester C<andy@petdance.com>

Brian Cassidy E<lt>bricas@cpan.orgE<gt>

Kirk Beers

=head1 COPYRIGHT AND LICENSE

Copyright 2008-2014 National Adult Literacy Database
Copyright 2015-2020 Andy Lester

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

