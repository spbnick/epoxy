Name:       epoxy
Version:    1
Release:    1%{?rev}%{?dist}
Summary:    Epoxy test framework

License:    GPLv2+
BuildArch:  noarch
Source:     %{name}-%{version}.tar.gz

Requires:   bash
Requires:   lua
Requires:   python

%description

%prep
%setup -q

%build
%configure
make %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}

%files
%doc
%{_bindir}/ep_*
%{_datadir}/%{name}

%changelog
